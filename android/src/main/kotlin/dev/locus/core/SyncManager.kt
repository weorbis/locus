package dev.locus.core

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import dev.locus.LocusPlugin
import dev.locus.storage.LocationStore
import dev.locus.storage.QueueStore
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.BufferedReader
import java.io.ByteArrayInputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

class SyncManager(
    private val context: Context,
    private val config: ConfigManager,
    private val locationStore: LocationStore,
    private val queueStore: QueueStore,
    private val listener: SyncListener
) {
    interface SyncListener {
        fun onHttpEvent(eventData: Map<String, Any>)
        fun onLog(level: String, message: String)
        fun onSyncRequest()

        /**
         * Called when SyncManager needs Dart to build a custom sync body.
         * Default implementation returns null to use native body builder.
         */
        fun buildSyncBody(
            locations: List<Map<String, Any>>,
            extras: Map<String, Any>,
            callback: (JSONObject?) -> Unit
        ) {
            callback(null)
        }

        /**
         * Called before sync to validate context.
         * Default implementation returns true to proceed.
         */
        fun onPreSyncValidation(
            locations: List<Map<String, Any>>,
            extras: Map<String, Any>,
            callback: (Boolean) -> Unit
        ) {
            callback(true)
        }

        /**
         * Called when native sync receives 401 and wants one background header
         * refresh attempt before pausing sync.
         */
        fun onHeadersRefresh(callback: (Map<String, String>?) -> Unit) {
            callback(null)
        }
    }

    private val executor: ExecutorService = Executors.newFixedThreadPool(4)
    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val prefs: SharedPreferences =
        context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE)
    private val locationSyncLock = Any()

    /**
     * Sync starts ACTIVE when Config.url is set. Pause is reserved for transport-level
     * auth failures (HTTP 401/403): those persist across process restarts via
     * ConfigManager.setSyncPauseReason to prevent retry storms from a stale token
     * surviving a process kill.
     *
     * Explicit [pause] by the host app stays in-memory only — "pause for now" intent
     * should not leak into the next process.
     *
     * Domain gating (shift not started, missing task context) belongs in
     * setPreSyncValidator, which rejects batches without blocking the transport.
     */
    @Volatile
    private var isSyncPaused: Boolean = isPersistedAuthPause(config.getSyncPauseReason())

    @Volatile
    private var isReleased = false

    @Volatile
    private var isLocationSyncInFlight = false

    @Volatile
    private var pendingLocationDrainRequested = false

    @Volatile
    var syncBodyBuilderEnabled = false

    /**
     * Tracks route contexts that exhausted all retries during the current
     * drain cycle. [selectNextLocationBatch] skips these so the drain can
     * advance to the next context group instead of re-selecting the same
     * failed batch in an infinite loop.
     *
     * Cleared at the start of each [resumeSync] call so that previously
     * failed contexts get a fresh chance on the next cycle.
     */
    private val drainExhaustedContexts = mutableSetOf<RouteContext>()

    private data class RouteContext(
        val ownerId: String,
        val driverId: String,
        val taskId: String,
        val trackingSessionId: String,
        val startedAt: String,
    )

    private data class LocationBatch(
        val payloads: List<Map<String, Any>>,
        val ids: List<String>,
    )

    init {
        val persistedReason = config.getSyncPauseReason()
        if (persistedReason != null && isPersistedAuthPause(persistedReason)) {
            Log.w(
                TAG,
                "SyncManager initialized - sync PAUSED (reason=$persistedReason). " +
                    "Call Locus.dataSync.resume() after refreshing auth."
            )
        } else {
            Log.i(TAG, "SyncManager initialized - sync active.")
        }
    }

    /**
     * Pauses sync due to a transport-level auth failure and persists the reason so the
     * pause survives process restart. Host must call [resumeSync] (typically after
     * refreshing credentials) to clear this.
     */
    private fun pauseForAuthFailure(status: Int) {
        val reason = "http_$status"
        isSyncPaused = true
        config.setSyncPauseReason(reason)
        Log.w(TAG, "http $status - sync paused (persisted as $reason)")
        emitPauseChange(true, reason)
    }

    /**
     * Emits a syncPauseChange event so the Dart side can keep its cache and any
     * reactive UI in sync without polling. `reason` is `null` when unpaused;
     * `"app"` for explicit [pause] calls; otherwise the HTTP status string
     * ("http_401" / "http_403") written by [pauseForAuthFailure].
     */
    private fun emitPauseChange(isPaused: Boolean, reason: String?) {
        val event = mutableMapOf<String, Any?>(
            "type" to "syncPauseChange",
            "data" to mapOf<String, Any?>(
                "isPaused" to isPaused,
                "reason" to reason
            )
        )
        @Suppress("UNCHECKED_CAST")
        listener.onHttpEvent(event as Map<String, Any>)
    }

    /** Current pause state — used by Dart cache priming and replay-on-attach. */
    fun getSyncPauseState(): Map<String, Any?> = mapOf(
        "isPaused" to isSyncPaused,
        "reason" to currentPauseReason()
    )

    /**
     * Re-emits the current pause state. Called by [LocusContainer.replayInitialState]
     * when a Dart listener first attaches so a process that cold-started in a
     * persisted-paused state still informs the newly-attached UI.
     */
    fun replaySyncPauseState() {
        emitPauseChange(isSyncPaused, currentPauseReason())
    }

    /**
     * Resolves the reason string that corresponds to the current in-memory paused
     * state. Persisted auth reasons (http_401/http_403) take precedence; otherwise
     * an explicit [pause] call is reported as "app". Returns null when unpaused.
     */
    private fun currentPauseReason(): String? {
        if (!isSyncPaused) return null
        return config.getSyncPauseReason() ?: "app"
    }

    fun release() {
        isReleased = true
        mainScope.cancel()
        executor.shutdown()
        // Don't force-terminate - let in-flight syncs complete gracefully
        // Callbacks will be ignored since isReleased is true
    }

    fun syncNow(currentPayload: Map<String, Any>?) {
        if (config.httpUrl.isNullOrEmpty()) {
            log("debug", "syncNow skipped: No URL configured. Set Config.url to enable sync.")
            return
        }
        if (isSyncPaused) {
            log(
                "debug",
                "syncNow skipped: sync is paused (reason=${config.getSyncPauseReason() ?: "app"}). " +
                    "Call resumeSync() after resolving."
            )
            return
        }
        if (config.batchSync) {
            requestLocationSync(config.maxBatchSize)
            return
        }
        currentPayload?.let { enqueueHttp(it, null, 0) }
    }

    fun pause() {
        if (isSyncPaused) return
        isSyncPaused = true
        Log.i(TAG, "Sync PAUSED by app request")
        emitPauseChange(true, "app")
    }

    fun resumeSync() {
        Log.i(TAG, "Sync RESUMED by app request - processing any pending locations...")
        val wasPaused = isSyncPaused
        isSyncPaused = false
        config.setSyncPauseReason(null)
        drainExhaustedContexts.clear()
        if (wasPaused) emitPauseChange(false, null)
        requestLocationSync(config.maxBatchSize)
        syncQueue(0)
    }

    /**
     * Check if sync is currently paused.
     */
    fun isPaused(): Boolean = isSyncPaused

    fun attemptBatchSync() {
        if (isSyncPaused) {
            Log.d("locus.SyncManager", "attemptBatchSync: skipped - sync is paused")
            return
        }

        val threshold = if (config.autoSyncThreshold > 0) {
            config.autoSyncThreshold
        } else {
            config.maxBatchSize
        }
        val backlog = buildBacklog()
        Log.d(
            "locus.SyncManager",
            "attemptBatchSync: pending=${backlog.pendingLocationCount}, threshold=$threshold"
        )
        if (backlog.pendingLocationCount < threshold) {
            Log.d(
                "locus.SyncManager",
                "attemptBatchSync: skipped - need $threshold records, have ${backlog.pendingLocationCount}"
            )
            return
        }

        requestLocationSync(config.maxBatchSize)
    }

    fun syncStoredLocations(limit: Int) {
        requestLocationSync(limit)
    }

    fun syncQueue(limit: Int): Int {
        if (config.httpUrl.isNullOrEmpty() || isSyncPaused) return 0
        
        val fetchLimit = if (limit > 0) limit else config.maxBatchSize
        val records = queueStore.readQueue(fetchLimit)
        var scheduled = 0
        val now = System.currentTimeMillis()
        
        for (record in records) {
            val nextRetryAt = (record["nextRetryAt"] as? Number)?.toLong() ?: 0L
            if (nextRetryAt > now) continue
            
            val id = record["id"] as? String ?: continue
            val payloadJson = record["payload"] as? String ?: continue
            
            try {
                val payload = QueueStore.parsePayload(payloadJson)
                val type = record["type"] as? String
                val key = record["idempotencyKey"] as? String ?: UUID.randomUUID().toString()
                val retryCount = (record["retryCount"] as? Number)?.toInt() ?: 0
                
                enqueueQueueHttp(payload, id, type, key, retryCount)
                scheduled++
            } catch (e: JSONException) {
                // Ignore malformed entries
            }
        }
        return scheduled
    }

    fun getLocationSyncBacklog(): Map<String, Any?> {
        val backlog = buildBacklog()
        return mapOf(
            "pendingLocationCount" to backlog.pendingLocationCount,
            "pendingBatchCount" to backlog.pendingBatchCount,
            "isPaused" to isSyncPaused,
            "quarantinedLocationCount" to backlog.quarantinedLocationCount,
            "lastSuccessAt" to readLastSuccessAt(),
            "lastFailureReason" to readLastFailureReason(),
            "groups" to backlog.groups,
        )
    }

    private data class BacklogSnapshot(
        val pendingLocationCount: Int,
        val pendingBatchCount: Int,
        val quarantinedLocationCount: Int,
        val groups: List<Map<String, Any>>,
    )

    private fun requestLocationSync(limit: Int) {
        if (config.httpUrl.isNullOrEmpty() || isSyncPaused) return

        val effectiveLimit = if (limit <= 0) config.maxBatchSize else limit
        val batch = synchronized(locationSyncLock) {
            pendingLocationDrainRequested = true
            if (isLocationSyncInFlight) {
                null
            } else {
                val nextBatch = selectNextLocationBatch(effectiveLimit)
                if (nextBatch == null) {
                    pendingLocationDrainRequested = false
                    null
                } else {
                    isLocationSyncInFlight = true
                    pendingLocationDrainRequested = false
                    nextBatch
                }
            }
        } ?: return

        enqueueHttpBatch(batch.payloads, batch.ids, 0)
    }

    /**
     * Advances the drain after a batch failure.
     *
     * When a retry is scheduled, the drain pauses for this batch — the retry
     * runs independently and restarts the drain on success.
     *
     * When retries are exhausted, the batch's [RouteContext] is added to
     * [drainExhaustedContexts] so [selectNextLocationBatch] skips it, and
     * the drain continues to the next context group.
     */
    private fun advanceDrainAfterFailure(payloads: List<Map<String, Any>>, retryScheduled: Boolean) {
        if (retryScheduled) {
            // Retry handles this batch independently. Pause drain — the retry's
            // eventual completeLocationSync(true) on success will restart it.
            completeLocationSync(false)
            return
        }
        // Retries exhausted. Mark this context so the drain skips it.
        payloads.firstOrNull()?.let { extractRouteContext(it) }?.let {
            drainExhaustedContexts.add(it)
        }
        completeLocationSync(true)
    }

    private fun completeLocationSync(continueDrain: Boolean) {
        val shouldContinue = synchronized(locationSyncLock) {
            isLocationSyncInFlight = false
            if (continueDrain) {
                pendingLocationDrainRequested = true
            }
            val next = pendingLocationDrainRequested
            pendingLocationDrainRequested = false
            next
        }

        if (shouldContinue && !isSyncPaused && !isReleased) {
            requestLocationSync(config.maxBatchSize)
        }
    }

    private fun selectNextLocationBatch(limit: Int): LocationBatch? {
        val records = locationStore.readLocations(0)
        if (records.isEmpty()) return null

        var selectedContext: RouteContext? = null
        val payloads = mutableListOf<Map<String, Any>>()
        val ids = mutableListOf<String>()

        for (record in records) {
            val payload = buildPayloadFromRecord(record)
            if (payload.isEmpty()) continue

            val context = extractRouteContext(payload) ?: continue
            // Skip contexts that exhausted all retries in this drain cycle.
            if (context in drainExhaustedContexts) continue
            if (selectedContext == null) {
                selectedContext = context
            }
            if (selectedContext != context) {
                continue
            }

            payloads.add(payload)
            (record["id"] as? String)?.let(ids::add)
            if (payloads.size >= limit) {
                break
            }
        }

        return if (payloads.isEmpty()) null else LocationBatch(payloads, ids)
    }

    private fun buildBacklog(): BacklogSnapshot {
        val records = locationStore.readLocations(0)
        val groupedCounts = linkedMapOf<RouteContext, Int>()
        var pendingLocationCount = 0
        var quarantinedLocationCount = 0

        for (record in records) {
            val payload = buildPayloadFromRecord(record)
            if (payload.isEmpty()) continue
            val context = extractRouteContext(payload)
            if (context == null) {
                quarantinedLocationCount++
                continue
            }
            pendingLocationCount++
            groupedCounts[context] = (groupedCounts[context] ?: 0) + 1
        }

        val pendingBatchCount = groupedCounts.values.sumOf { count ->
            max(1, (count + config.maxBatchSize - 1) / config.maxBatchSize)
        }
        val groups = groupedCounts.entries.map { (context, count) ->
            mapOf(
                "ownerId" to context.ownerId,
                "driverId" to context.driverId,
                "taskId" to context.taskId,
                "trackingSessionId" to context.trackingSessionId,
                "startedAt" to context.startedAt,
                "pendingLocationCount" to count,
            )
        }

        return BacklogSnapshot(
            pendingLocationCount = pendingLocationCount,
            pendingBatchCount = pendingBatchCount,
            quarantinedLocationCount = quarantinedLocationCount,
            groups = groups,
        )
    }

    private fun extractRouteContext(payload: Map<String, Any>): RouteContext? {
        val extras = payload["extras"] as? Map<*, *> ?: return null
        val ownerId = extras["owner_id"]?.toString().orEmpty()
        val driverId = extras["driver_id"]?.toString().orEmpty()
        val taskId = extras["task_id"]?.toString().orEmpty()
        val trackingSessionId = extras["tracking_session_id"]?.toString().orEmpty()
        val startedAt = extras["started_at"]?.toString().orEmpty()

        if (ownerId.isBlank() ||
            driverId.isBlank() ||
            taskId.isBlank() ||
            trackingSessionId.isBlank() ||
            startedAt.isBlank()
        ) {
            return null
        }

        return RouteContext(
            ownerId = ownerId,
            driverId = driverId,
            taskId = taskId,
            trackingSessionId = trackingSessionId,
            startedAt = startedAt,
        )
    }

    private fun recordSyncSuccess() {
        prefs.edit()
            .putLong(KEY_LAST_LOCATION_SYNC_SUCCESS_AT, System.currentTimeMillis())
            .remove(KEY_LAST_LOCATION_SYNC_FAILURE_REASON)
            .apply()
        // Any 2xx proves auth is valid — clear the persisted auth-failure marker
        // defensively in case resumeSync() wasn't explicitly called after token refresh.
        // Only notify Dart if the persisted reason actually changed (avoids churn on
        // every successful batch).
        val hadPersistedReason = config.getSyncPauseReason() != null
        config.setSyncPauseReason(null)
        if (hadPersistedReason && !isSyncPaused) {
            emitPauseChange(false, null)
        }
    }

    private fun recordSyncFailure(reason: String) {
        prefs.edit()
            .putString(KEY_LAST_LOCATION_SYNC_FAILURE_REASON, reason)
            .apply()
    }

    private fun readLastSuccessAt(): String? {
        val timestamp = prefs.getLong(KEY_LAST_LOCATION_SYNC_SUCCESS_AT, 0L)
        if (timestamp <= 0L) return null
        return Instant.ofEpochMilli(timestamp).toString()
    }

    private fun readLastFailureReason(): String? =
        prefs.getString(KEY_LAST_LOCATION_SYNC_FAILURE_REASON, null)

    private fun enqueueHttp(payload: Map<String, Any>, idsToDelete: List<String>?, attempt: Int) {
        if (isSyncPaused) return

        val locationPayload = buildPayloadFromRecord(payload)
        if (locationPayload.isEmpty()) return

        listener.onPreSyncValidation(listOf(locationPayload), config.extras) { proceed ->
            if (!proceed || isReleased) {
                if (!proceed && !isReleased) {
                    emitHttpEvent(0, false, "pre_sync_validator_rejected")
                    log(
                        "error",
                        "pre-sync validator rejected locations=1 extras=${JSONObject(config.extras).toString()}"
                    )
                    recordSyncFailure("pre_sync_validator_rejected")
                }
                advanceDrainAfterFailure(listOf(locationPayload), retryScheduled = false)
                return@onPreSyncValidation
            }

            if (syncBodyBuilderEnabled) {
                // Ask Dart to build the sync body asynchronously
                listener.buildSyncBody(listOf(locationPayload), config.extras) { customBody ->
                    if (isReleased) return@buildSyncBody

                    executor.execute {
                        if (customBody == null) {
                            emitHttpEvent(0, false, "sync_body_builder_failed")
                            log(
                                "error",
                                "sync body builder failed locations=1 extras=${JSONObject(config.extras).toString()}"
                            )
                            recordSyncFailure("sync_body_builder_failed")
                            val retryScheduled = scheduleHttpRetry(locationPayload, idsToDelete, attempt + 1)
                            advanceDrainAfterFailure(listOf(locationPayload), retryScheduled)
                            return@execute
                        }
                        listener.onSyncRequest()
                        val body = customBody.apply {
                            config.httpParams.forEach { (key, value) ->
                                put(key, value)
                            }
                        }
                        performHttpRequest(body, idsToDelete, attempt, locationPayload)
                    }
                }
            } else {
                executor.execute {
                    listener.onSyncRequest()
                    val body = buildHttpBody(locationPayload, null).apply {
                        config.httpParams.forEach { (key, value) ->
                            put(key, value)
                        }
                    }
                    performHttpRequest(body, idsToDelete, attempt, locationPayload)
                }
            }
        }
    }

    private fun enqueueHttpBatch(payloads: List<Map<String, Any>>, idsToDelete: List<String>, attempt: Int) {
        if (isSyncPaused) return

        listener.onPreSyncValidation(payloads, config.extras) { proceed ->
            if (!proceed || isReleased) {
                if (!proceed && !isReleased) {
                    emitHttpEvent(0, false, "pre_sync_validator_rejected")
                    log(
                        "error",
                        "pre-sync validator rejected locations=${payloads.size} extras=${JSONObject(config.extras).toString()}"
                    )
                    recordSyncFailure("pre_sync_validator_rejected")
                }
                advanceDrainAfterFailure(payloads, retryScheduled = false)
                return@onPreSyncValidation
            }

            if (syncBodyBuilderEnabled) {
                // Ask Dart to build the sync body asynchronously
                listener.buildSyncBody(payloads, config.extras) { customBody ->
                    if (isReleased) return@buildSyncBody

                    executor.execute {
                        if (customBody == null) {
                            emitHttpEvent(0, false, "sync_body_builder_failed")
                            log(
                                "error",
                                "sync body builder failed locations=${payloads.size} extras=${JSONObject(config.extras).toString()}"
                            )
                            recordSyncFailure("sync_body_builder_failed")
                            val retryScheduled = scheduleBatchRetry(payloads, idsToDelete, attempt + 1)
                            advanceDrainAfterFailure(payloads, retryScheduled)
                            return@execute
                        }
                        listener.onSyncRequest()
                        val body = customBody.apply {
                            config.httpParams.forEach { (key, value) ->
                                put(key, value)
                            }
                        }
                        performBatchHttpRequest(body, idsToDelete, attempt, payloads)
                    }
                }
            } else {
                executor.execute {
                    listener.onSyncRequest()
                    val body = buildHttpBody(null, payloads).apply {
                        config.httpParams.forEach { (key, value) ->
                            put(key, value)
                        }
                    }
                    performBatchHttpRequest(body, idsToDelete, attempt, payloads)
                }
            }
        }
    }

    private fun enqueueQueueHttp(
        payload: Map<String, Any>,
        id: String,
        type: String?,
        idempotencyKey: String,
        attempt: Int
    ) {
        if (isSyncPaused) return
        
        executor.execute {
            listener.onSyncRequest()
            var connection: HttpURLConnection? = null
            try {
                val body = buildQueueBody(payload, id, type, idempotencyKey).apply {
                    config.httpParams.forEach { (key, value) ->
                        put(key, value)
                    }
                }

                connection = (URL(config.httpUrl).openConnection() as HttpURLConnection).apply {
                    requestMethod = config.httpMethod
                    connectTimeout = config.httpTimeoutMs
                    readTimeout = config.httpTimeoutMs
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    config.httpHeaders.toMap().forEach { (key, value) ->
                        setRequestProperty(sanitizeHeaderKey(key), sanitizeHeaderValue(value.toString()))
                    }
                    config.idempotencyHeader?.let { header ->
                        setRequestProperty(sanitizeHeaderKey(header), idempotencyKey)
                    }
                }

                connection.outputStream.use { output ->
                    output.write(body.toString().toByteArray())
                    output.flush()
                }

                val status = connection.responseCode
                val stream = if (status >= 400) {
                    connection.errorStream ?: ByteArrayInputStream(ByteArray(0))
                } else {
                    connection.inputStream
                }

                val responseText = BufferedReader(InputStreamReader(stream)).use { reader ->
                    reader.readText()
                }

                val ok = status in 200..299
                if (ok) {
                    queueStore.deleteByIds(listOf(id))
                }

                emitHttpEvent(status, ok, responseText)
                log("info", "http $status")

                when {
                    status == 401 || status == 403 -> pauseForAuthFailure(status)
                    !ok -> scheduleQueueRetry(payload, id, type, idempotencyKey, attempt + 1)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Queue HTTP sync failed: ${sanitizeError(e)}")
                emitHttpEvent(0, false, e.message)
                log("error", "http error ${sanitizeError(e)}")
                scheduleQueueRetry(payload, id, type, idempotencyKey, attempt + 1)
            } finally {
                connection?.disconnect()
            }
        }
    }

    private fun buildHttpBody(
        locationPayload: Map<String, Any>?,
        locations: List<Map<String, Any>>?
    ): JSONObject = JSONObject().apply {
        // Merge extras at top level first (these are user-defined envelope fields)
        config.httpExtras?.forEach { (key, value) ->
            put(key, value)
        }

        // Add locations under the specified root property
        val rootProperty = config.httpRootProperty?.takeIf { it.isNotEmpty() }
        
        when {
            locations != null -> {
                val list = JSONArray().apply {
                    locations.forEach { put(JSONObject(it)) }
                }
                put(rootProperty ?: "locations", list)
            }
            locationPayload != null -> {
                val payload = JSONObject(locationPayload)
                put(rootProperty ?: "location", payload)
            }
        }
    }

    private fun buildQueueBody(
        payload: Map<String, Any>,
        id: String,
        type: String?,
        idempotencyKey: String?
    ): JSONObject = JSONObject().apply {
        val rootProperty = config.httpRootProperty?.takeIf { it.isNotEmpty() } ?: "payload"
        put(rootProperty, JSONObject(payload))
        put("queueId", id)
        type?.let { put("type", it) }
        idempotencyKey?.let { put("idempotencyKey", it) }
    }

    private fun performHttpRequest(
        body: JSONObject,
        idsToDelete: List<String>?,
        attempt: Int,
        originalPayload: Map<String, Any>,
        allowRecovery: Boolean = true,
    ) {
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(config.httpUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = config.httpMethod
                connectTimeout = config.httpTimeoutMs
                readTimeout = config.httpTimeoutMs
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                config.httpHeaders.toMap().forEach { (key, value) ->
                    setRequestProperty(sanitizeHeaderKey(key), sanitizeHeaderValue(value.toString()))
                }
            }

            connection.outputStream.use { output ->
                output.write(body.toString().toByteArray())
                output.flush()
            }

            val status = connection.responseCode
            val stream = if (status >= 400) {
                connection.errorStream ?: ByteArrayInputStream(ByteArray(0))
            } else {
                connection.inputStream
            }

            val responseText = BufferedReader(InputStreamReader(stream)).use { reader ->
                reader.readText()
            }

            if (status == 401 && allowRecovery) {
                attemptLocationHeadersRecovery {
                    performHttpRequest(
                        body = body,
                        idsToDelete = idsToDelete,
                        attempt = attempt,
                        originalPayload = originalPayload,
                        allowRecovery = false,
                    )
                }
                return
            }

            val ok = status in 200..299
            if (ok && !idsToDelete.isNullOrEmpty()) {
                locationStore.deleteLocations(idsToDelete)
                recordSyncSuccess()
            }

            emitHttpEvent(status, ok, responseText)
            log(if (ok) "info" else "error", "http $status${if (ok) "" else " $responseText"}")

            when {
                status == 401 || status == 403 -> {
                    recordSyncFailure("http_$status")
                    pauseForAuthFailure(status)
                    completeLocationSync(false)
                }
                !ok -> {
                    recordSyncFailure("http_$status")
                    val retryScheduled = scheduleHttpRetry(originalPayload, idsToDelete, attempt + 1)
                    advanceDrainAfterFailure(listOf(originalPayload), retryScheduled)
                }
                else -> completeLocationSync(true)
            }
        } catch (e: Exception) {
            Log.e(TAG, "HTTP sync failed: ${sanitizeError(e)}")
            emitHttpEvent(0, false, e.message)
            log("error", "http error ${sanitizeError(e)}")
            recordSyncFailure("exception:${e.javaClass.simpleName}")
            val retryScheduled = scheduleHttpRetry(originalPayload, idsToDelete, attempt + 1)
            advanceDrainAfterFailure(listOf(originalPayload), retryScheduled)
        } finally {
            connection?.disconnect()
        }
    }

    private fun performBatchHttpRequest(
        body: JSONObject,
        idsToDelete: List<String>,
        attempt: Int,
        payloads: List<Map<String, Any>>,
        allowRecovery: Boolean = true,
    ) {
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(config.httpUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = config.httpMethod
                connectTimeout = config.httpTimeoutMs
                readTimeout = config.httpTimeoutMs
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                config.httpHeaders.toMap().forEach { (key, value) ->
                    setRequestProperty(sanitizeHeaderKey(key), sanitizeHeaderValue(value.toString()))
                }
            }

            connection.outputStream.use { output ->
                output.write(body.toString().toByteArray())
                output.flush()
            }

            val status = connection.responseCode
            val stream = if (status >= 400) {
                connection.errorStream ?: ByteArrayInputStream(ByteArray(0))
            } else {
                connection.inputStream
            }

            val responseText = BufferedReader(InputStreamReader(stream)).use { reader ->
                reader.readText()
            }

            if (status == 401 && allowRecovery) {
                attemptLocationHeadersRecovery {
                    performBatchHttpRequest(
                        body = body,
                        idsToDelete = idsToDelete,
                        attempt = attempt,
                        payloads = payloads,
                        allowRecovery = false,
                    )
                }
                return
            }

            val ok = status in 200..299
            if (ok && idsToDelete.isNotEmpty()) {
                locationStore.deleteLocations(idsToDelete)
                recordSyncSuccess()
            }

            emitHttpEvent(status, ok, responseText)
            log(if (ok) "info" else "error", "http $status${if (ok) "" else " $responseText"}")

            when {
                status == 401 || status == 403 -> {
                    recordSyncFailure("http_$status")
                    pauseForAuthFailure(status)
                    completeLocationSync(false)
                }
                !ok -> {
                    recordSyncFailure("http_$status")
                    val retryScheduled = scheduleBatchRetry(payloads, idsToDelete, attempt + 1)
                    advanceDrainAfterFailure(payloads, retryScheduled)
                }
                else -> completeLocationSync(true)
            }
        } catch (e: Exception) {
            Log.e(TAG, "HTTP sync failed: ${sanitizeError(e)}")
            emitHttpEvent(0, false, e.message)
            log("error", "http error ${sanitizeError(e)}")
            recordSyncFailure("exception:${e.javaClass.simpleName}")
            val retryScheduled = scheduleBatchRetry(payloads, idsToDelete, attempt + 1)
            advanceDrainAfterFailure(payloads, retryScheduled)
        } finally {
            connection?.disconnect()
        }
    }

    private fun attemptLocationHeadersRecovery(retry: () -> Unit) {
        listener.onHeadersRefresh { headers ->
            val recovered = headers?.get("Authorization")?.isNotBlank() == true
            if (recovered) {
                val newHeaders = java.util.concurrent.ConcurrentHashMap<String, Any>(headers)
                config.httpHeaders = newHeaders
                retry()
                return@onHeadersRefresh
            }

            recordSyncFailure("http_401")
            emitHttpEvent(401, false, "unauthorized")
            pauseForAuthFailure(401)
            completeLocationSync(false)
        }
    }

    /**
     * Schedules an exponential-backoff retry for a failed batch.
     *
     * @return `true` if a retry was scheduled, `false` if retries are exhausted.
     */
    private fun scheduleBatchRetry(payloads: List<Map<String, Any>>, idsToDelete: List<String>, attempt: Int): Boolean {
        if (isReleased || attempt > config.maxRetry || config.httpUrl.isNullOrEmpty()) return false

        val delay = calculateRetryDelay(attempt)
        mainScope.launch {
            delay(delay)
            if (!isReleased) enqueueHttpBatch(payloads, idsToDelete, attempt)
        }
        return true
    }

    /**
     * Schedules an exponential-backoff retry for a single failed location.
     *
     * @return `true` if a retry was scheduled, `false` if retries are exhausted.
     */
    private fun scheduleHttpRetry(payload: Map<String, Any>, idsToDelete: List<String>?, attempt: Int): Boolean {
        if (isReleased || attempt > config.maxRetry || config.httpUrl.isNullOrEmpty()) return false

        val delay = calculateRetryDelay(attempt)
        mainScope.launch {
            delay(delay)
            if (!isReleased) enqueueHttp(payload, idsToDelete, attempt)
        }
        return true
    }

    private fun scheduleQueueRetry(
        payload: Map<String, Any>,
        id: String,
        type: String?,
        idempotencyKey: String,
        attempt: Int
    ) {
        if (isReleased || attempt > config.maxRetry || config.httpUrl.isNullOrEmpty()) return
        
        val delay = calculateRetryDelay(attempt)
        val nextRetryAt = System.currentTimeMillis() + delay
        queueStore.updateRetry(id, attempt, nextRetryAt)
        mainScope.launch {
            delay(delay)
            if (!isReleased) enqueueQueueHttp(payload, id, type, idempotencyKey, attempt)
        }
    }

    private fun calculateRetryDelay(attempt: Int): Long {
        val delay = (config.retryDelayMs * config.retryDelayMultiplier.pow(max(0, attempt - 1))).toLong()
        return max(config.retryDelayMs.toLong(), min(delay, config.maxRetryDelayMs.toLong()))
    }

    private fun emitHttpEvent(status: Int, ok: Boolean, responseText: String?) {
        val httpEvent = mapOf(
            "type" to "http",
            "data" to mapOf(
                "status" to status,
                "ok" to ok,
                "responseText" to (responseText ?: "")
            )
        )
        listener.onHttpEvent(httpEvent)
    }

    private fun log(level: String, message: String) {
        listener.onLog(level, message)
    }

    fun buildPayloadFromRecord(record: Map<String, Any>?): Map<String, Any> {
        if (record == null) return emptyMap()
        
        val id = record["id"]
        val timestampValue = record["timestamp"]
        val latitude = record["latitude"]
        val longitude = record["longitude"]
        val accuracy = record["accuracy"]
        val speed = record["speed"]
        val heading = record["heading"]
        val altitude = record["altitude"]
        
        if (latitude == null || longitude == null || accuracy == null || timestampValue == null) {
            return emptyMap()
        }
        
        val coords = mapOf(
            "latitude" to latitude,
            "longitude" to longitude,
            "accuracy" to accuracy,
            "speed" to speed,
            "heading" to heading,
            "altitude" to altitude
        )

        val activity = buildMap<String, Any> {
            (record["activity_type"] as? String)?.let { put("type", it) }
            (record["activity_confidence"] as? Number)?.toInt()?.let { put("confidence", it) }
        }

        val timestamp = (timestampValue as? Number)?.toLong() ?: System.currentTimeMillis()
        
        return buildMap {
            put("uuid", (id as? String) ?: UUID.randomUUID().toString())
            put("timestamp", Instant.ofEpochMilli(timestamp).toString())
            put("coords", coords)
            if (activity.isNotEmpty()) put("activity", activity)
            record["event"]?.let { put("event", it) }
            record["is_moving"]?.let { put("is_moving", it) }
            record["odometer"]?.let { put("odometer", it) }
            when (val rawExtras = record["extras"]) {
                is Map<*, *> -> put("extras", rawExtras)
                else -> (record["extras_json"] as? String)?.takeIf { it.isNotBlank() }?.let { extrasJson ->
                    try {
                        put("extras", JSONObject(extrasJson).toMap())
                    } catch (_: JSONException) {
                    }
                }
            }
        }
    }

    private fun JSONObject.toMap(): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val keys = keys()
        while (keys.hasNext()) {
            val key = keys.next()
            when (val value = get(key)) {
                JSONObject.NULL -> {
                }
                is JSONObject -> map[key] = value.toMap()
                is JSONArray -> map[key] = value.toList()
                else -> map[key] = value
            }
        }
        return map
    }

    private fun JSONArray.toList(): List<Any> {
        val list = mutableListOf<Any>()
        for (index in 0 until length()) {
            when (val value = get(index)) {
                JSONObject.NULL -> {
                }
                is JSONObject -> list.add(value.toMap())
                is JSONArray -> list.add(value.toList())
                else -> list.add(value)
            }
        }
        return list
    }

    companion object {
        private const val TAG = "locus"
        private const val KEY_LAST_LOCATION_SYNC_SUCCESS_AT =
            "bg_last_location_sync_success_at"
        private const val KEY_LAST_LOCATION_SYNC_FAILURE_REASON =
            "bg_last_location_sync_failure_reason"

        internal const val REASON_HTTP_401 = "http_401"
        internal const val REASON_HTTP_403 = "http_403"
        private val AUTH_FAILURE_REASONS = setOf(REASON_HTTP_401, REASON_HTTP_403)

        /** True when the persisted reason is an auth-class failure the host must resolve. */
        internal fun isPersistedAuthPause(reason: String?): Boolean =
            reason != null && reason in AUTH_FAILURE_REASONS

        private fun sanitizeError(e: Exception): String =
            e.javaClass.simpleName + if (e.message?.contains("://") == true) " (network)" else ": ${e.message}"

        private val headerInjectionPattern = Regex("[\r\n]")

        private fun sanitizeHeaderKey(key: String): String {
            return key.replace(headerInjectionPattern, "").trim()
        }

        private fun sanitizeHeaderValue(value: String): String {
            return value.replace(headerInjectionPattern, "").trim()
        }
    }
}
