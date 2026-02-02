package dev.locus.core

import android.content.Context
import android.util.Log
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
    }

    private val executor: ExecutorService = Executors.newFixedThreadPool(4)
    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    /**
     * Sync is PAUSED by default on startup.
     *
     * This prevents race conditions where sync fires before the app has established
     * required context (auth tokens, task IDs, etc.) after app restart.
     *
     * The app MUST call resumeSync() after initialization is complete.
     * This is typically done after:
     * 1. Locus.ready() is called
     * 2. Auth tokens are refreshed
     * 3. Tracking context is restored (task ID, owner ID, etc.)
     */
    @Volatile
    private var isSyncPaused = true

    @Volatile
    private var isReleased = false

    @Volatile
    var syncBodyBuilderEnabled = false

    init {
        Log.i(TAG, "SyncManager initialized - sync PAUSED by default (call resumeSync() when app is ready)")
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
            log("debug", "syncNow skipped: Sync is paused (401 received). Call resumeSync() after token refresh.")
            return
        }
        if (config.batchSync) {
            syncStoredLocations(config.maxBatchSize)
            return
        }
        currentPayload?.let { enqueueHttp(it, null, 0) }
    }

    fun pause() {
        isSyncPaused = true
        Log.i(TAG, "Sync PAUSED by app request")
    }

    fun resumeSync() {
        Log.i(TAG, "Sync RESUMED by app request - processing any pending locations...")
        isSyncPaused = false
        syncStoredLocations(config.maxBatchSize)
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
        
        val threshold = if (config.autoSyncThreshold > 0) config.autoSyncThreshold else config.maxBatchSize
        val effectiveThreshold = if (threshold <= 0) config.maxBatchSize else threshold
        val fetchLimit = max(effectiveThreshold, config.maxBatchSize)
        
        val records = locationStore.readLocations(fetchLimit)
        Log.d("locus.SyncManager", "attemptBatchSync: records=${records.size}, threshold=$effectiveThreshold")
        
        if (records.size < effectiveThreshold) {
            Log.d("locus.SyncManager", "attemptBatchSync: skipped - need $effectiveThreshold records, have ${records.size}")
            return
        }
        
        val sendCount = min(config.maxBatchSize, records.size)
        val batch = records.subList(0, sendCount)
        
        val payloads = mutableListOf<Map<String, Any>>()
        val ids = mutableListOf<String>()
        
        for (record in batch) {
            val payload = buildPayloadFromRecord(record)
            if (payload.isNotEmpty()) {
                payloads.add(payload)
            }
            (record["id"] as? String)?.let { ids.add(it) }
        }
        
        if (payloads.isNotEmpty()) {
            Log.d("locus.SyncManager", "attemptBatchSync: sending ${payloads.size} locations...")
            enqueueHttpBatch(payloads, ids, 0)
        }
    }

    fun syncStoredLocations(limit: Int) {
        if (isSyncPaused) return
        
        val effectiveLimit = if (limit <= 0) config.maxBatchSize else limit
        val records = locationStore.readLocations(effectiveLimit)
        if (records.isEmpty()) return
        
        val payloads = mutableListOf<Map<String, Any>>()
        val ids = mutableListOf<String>()
        
        for (record in records) {
            val payload = buildPayloadFromRecord(record)
            if (payload.isNotEmpty()) {
                payloads.add(payload)
            }
            (record["id"] as? String)?.let { ids.add(it) }
        }
        
        if (payloads.isNotEmpty()) {
            enqueueHttpBatch(payloads, ids, 0)
        }
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

    private fun enqueueHttp(payload: Map<String, Any>, idsToDelete: List<String>?, attempt: Int) {
        if (isSyncPaused) return

        val locationPayload = buildPayloadFromRecord(payload)
        if (locationPayload.isEmpty()) return

        listener.onPreSyncValidation(listOf(locationPayload), config.extras) { proceed ->
            if (!proceed || isReleased) return@onPreSyncValidation

            if (syncBodyBuilderEnabled) {
                // Ask Dart to build the sync body asynchronously
                listener.buildSyncBody(listOf(locationPayload), config.extras) { customBody ->
                    if (isReleased) return@buildSyncBody

                    executor.execute {
                        listener.onSyncRequest()
                        val body = (customBody ?: buildHttpBody(locationPayload, null)).apply {
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
            if (!proceed || isReleased) return@onPreSyncValidation

            if (syncBodyBuilderEnabled) {
                // Ask Dart to build the sync body asynchronously
                listener.buildSyncBody(payloads, config.extras) { customBody ->
                    if (isReleased) return@buildSyncBody

                    executor.execute {
                        listener.onSyncRequest()
                        val body = (customBody ?: buildHttpBody(null, payloads)).apply {
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
            try {
                val body = buildQueueBody(payload, id, type, idempotencyKey).apply {
                    config.httpParams.forEach { (key, value) ->
                        put(key, value)
                    }
                }

                val connection = (URL(config.httpUrl).openConnection() as HttpURLConnection).apply {
                    requestMethod = config.httpMethod
                    connectTimeout = config.httpTimeoutMs
                    readTimeout = config.httpTimeoutMs
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    config.httpHeaders.forEach { (key, value) ->
                        setRequestProperty(key, value.toString())
                    }
                    config.idempotencyHeader?.let { header ->
                        setRequestProperty(header, idempotencyKey)
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
                    status == 401 -> {
                        isSyncPaused = true
                        log("error", "http 401 - sync paused")
                    }
                    !ok -> scheduleQueueRetry(payload, id, type, idempotencyKey, attempt + 1)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Queue HTTP sync failed: ${e.message}")
                emitHttpEvent(0, false, e.message)
                log("error", "http error ${e.message}")
                scheduleQueueRetry(payload, id, type, idempotencyKey, attempt + 1)
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
        originalPayload: Map<String, Any>
    ) {
        try {
            val connection = (URL(config.httpUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = config.httpMethod
                connectTimeout = config.httpTimeoutMs
                readTimeout = config.httpTimeoutMs
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                config.httpHeaders.forEach { (key, value) ->
                    setRequestProperty(key, value.toString())
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
            if (ok && !idsToDelete.isNullOrEmpty()) {
                locationStore.deleteLocations(idsToDelete)
            }

            emitHttpEvent(status, ok, responseText)
            log("info", "http $status")

            when {
                status == 401 -> {
                    isSyncPaused = true
                    log("error", "http 401 - sync paused")
                }
                !ok -> scheduleHttpRetry(originalPayload, idsToDelete, attempt + 1)
            }
        } catch (e: Exception) {
            Log.e(TAG, "HTTP sync failed: ${e.message}")
            emitHttpEvent(0, false, e.message)
            log("error", "http error ${e.message}")
            scheduleHttpRetry(originalPayload, idsToDelete, attempt + 1)
        }
    }

    private fun performBatchHttpRequest(
        body: JSONObject,
        idsToDelete: List<String>,
        attempt: Int,
        payloads: List<Map<String, Any>>
    ) {
        try {
            val connection = (URL(config.httpUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = config.httpMethod
                connectTimeout = config.httpTimeoutMs
                readTimeout = config.httpTimeoutMs
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                config.httpHeaders.forEach { (key, value) ->
                    setRequestProperty(key, value.toString())
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
            if (ok && idsToDelete.isNotEmpty()) {
                locationStore.deleteLocations(idsToDelete)
            }

            emitHttpEvent(status, ok, responseText)
            log("info", "http $status")

            when {
                status == 401 -> {
                    isSyncPaused = true
                    log("error", "http 401 - sync paused")
                }
                !ok -> scheduleBatchRetry(payloads, idsToDelete, attempt + 1)
            }
        } catch (e: Exception) {
            Log.e(TAG, "HTTP sync failed: ${e.message}")
            emitHttpEvent(0, false, e.message)
            log("error", "http error ${e.message}")
            scheduleBatchRetry(payloads, idsToDelete, attempt + 1)
        }
    }

    private fun scheduleBatchRetry(payloads: List<Map<String, Any>>, idsToDelete: List<String>, attempt: Int) {
        if (isReleased || attempt > config.maxRetry || config.httpUrl.isNullOrEmpty()) return
        
        val delay = calculateRetryDelay(attempt)
        mainScope.launch {
            delay(delay)
            if (!isReleased) enqueueHttpBatch(payloads, idsToDelete, attempt)
        }
    }

    private fun scheduleHttpRetry(payload: Map<String, Any>, idsToDelete: List<String>?, attempt: Int) {
        if (isReleased || attempt > config.maxRetry || config.httpUrl.isNullOrEmpty()) return
        
        val delay = calculateRetryDelay(attempt)
        mainScope.launch {
            delay(delay)
            if (!isReleased) enqueueHttp(payload, idsToDelete, attempt)
        }
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
        }
    }

    companion object {
        private const val TAG = "locus"

        private val headerInjectionPattern = Regex("[\r\n]")

        private fun sanitizeHeaderKey(key: String): String {
            return key.replace(headerInjectionPattern, "").trim()
        }

        private fun sanitizeHeaderValue(value: String): String {
            return value.replace(headerInjectionPattern, "").trim()
        }
    }
}
