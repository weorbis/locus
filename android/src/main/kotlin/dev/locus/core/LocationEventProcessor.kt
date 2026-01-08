package dev.locus.core

import android.util.Log

class LocationEventProcessor(
    private val config: ConfigManager,
    private val stateManager: StateManager,
    private val syncManager: SyncManager,
    private val eventDispatcher: EventDispatcher,
    private val autoSyncChecker: AutoSyncChecker
) {
    fun dispatch(eventName: String, payload: Map<String, Any>) {
        Log.d("locus.EventProcessor", ">>> dispatch called: eventName=$eventName")
        val event = mapOf(
            "type" to eventName,
            "data" to payload
        )
        eventDispatcher.sendEvent(event)

        Log.d("locus.EventProcessor", ">>> privacyModeEnabled=${config.privacyModeEnabled}")
        if (!config.privacyModeEnabled) {
            val shouldPersist = PersistencePolicy.shouldPersist(config, eventName)
            Log.d("locus.EventProcessor", ">>> shouldPersist=$shouldPersist, batchSync=${config.batchSync}, persistMode=${config.persistMode}")
            if (shouldPersist) {
                Log.d("locus.EventProcessor", ">>> Storing location payload...")
                stateManager.storeLocationPayload(payload, config.maxDaysToPersist, config.maxRecordsToPersist)
            }
            if (config.autoSync && !config.httpUrl.isNullOrEmpty() && autoSyncChecker.isAutoSyncAllowed()) {
                Log.d("locus.EventProcessor", ">>> Auto sync triggered")
                if (config.batchSync) {
                    syncManager.attemptBatchSync()
                } else {
                    syncManager.syncNow(payload)
                }
            }
        }
    }

    fun syncNow(payload: Map<String, Any>?) {
        syncManager.syncNow(payload)
    }
}
