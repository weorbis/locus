package dev.locus.core

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.os.Process
import android.util.Log
import dev.locus.service.AndroidForegroundServiceGateway
import dev.locus.storage.LocationStore
import java.util.concurrent.Callable
import java.util.concurrent.Executors

/** Test-APK-only command host for the shell process-recovery smoke test. */
class RecoveryTestActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        when (intent?.action) {
            RecoveryTestContract.ACTION_REPORT -> {
                RecoveryTestCommands.reportState(this)
                finish()
            }
            RecoveryTestContract.ACTION_STOP -> {
                RecoveryTestCommands.stopTracking(this)
                finish()
            }
            else -> {
                RecoveryTestCommands.armRecoveryFixture(this)
                // Keep a normal task record while moving the fixture out of
                // the foreground. Removing the task would exercise
                // onTaskRemoved rather than isolated OS process death.
                moveTaskToBack(true)
            }
        }
    }
}

internal object RecoveryTestCommands {
    // Encrypted stores are prepared off the main thread and refuse main-thread callers while that runs.
    private fun <T> offMainThread(block: () -> T): T {
        val executor = Executors.newSingleThreadExecutor()
        try {
            return executor.submit(Callable(block)).get()
        } finally {
            executor.shutdown()
        }
    }

    fun armRecoveryFixture(context: Context) {
        val manager = ConfigManager(context)
        offMainThread { LocationStore(context).use { it.clear() } }
        check(manager.persistPrivacyMode(false)) {
            "Recovery fixture must begin outside privacy mode"
        }
        val persisted = manager.applyConfig(
            mapOf(
                "foregroundService" to true,
                "disableMotionActivityUpdates" to true,
                "stopOnTerminate" to false,
                "persistMode" to "location",
                "desiredAccuracy" to "navigation",
                "distanceFilter" to 0,
                "stationaryRadius" to 0,
                "locationUpdateInterval" to 1_000,
                "fastestLocationUpdateInterval" to 500,
                "notification" to mapOf(
                    "title" to "Locus recovery test",
                    "text" to "Verifying process recovery",
                    "importance" to 1,
                ),
            ),
        )
        check(persisted && manager.setTrackingActive(true)) {
            "Recovery fixture must persist config and desired tracking state"
        }
        check(AndroidForegroundServiceGateway(context).start(manager)) {
            "Recovery fixture foreground service must be accepted for start"
        }
        Log.i(RecoveryTestContract.TAG, "armed pid=${Process.myPid()}")
    }

    fun stopTracking(context: Context) {
        val manager = ConfigManager(context)
        val persisted = LocusContainer.peek()?.locationTracker?.stopTracking()
            ?: manager.setTrackingActive(false)
        AndroidForegroundServiceGateway(context).stop()
        check(persisted) { "Explicit stop must clear durable tracking intent" }
        Log.i(RecoveryTestContract.TAG, "stopped pid=${Process.myPid()} trackingDesired=false")
    }

    fun reportState(context: Context) {
        val locations = offMainThread { LocationStore(context).use { it.readLocations(0) } }
        val latestTimestamp = (locations.lastOrNull()?.get("timestamp") as? Number)?.toLong() ?: -1L
        val container = LocusContainer.peek()
        Log.i(
            RecoveryTestContract.TAG,
            "state pid=${Process.myPid()} " +
                "trackingDesired=${ConfigManager(context).isTrackingActivePersisted()} " +
                "runtimeEnabled=${container?.locationTracker?.isEnabled() == true} " +
                "locationCount=${locations.size} latestTimestamp=$latestTimestamp " +
                "reportedAt=${System.currentTimeMillis()}",
        )
    }
}

internal object RecoveryTestContract {
    const val ACTION_ARM = "dev.locus.test.action.ARM_RECOVERY"
    const val ACTION_REPORT = "dev.locus.test.action.REPORT_RECOVERY"
    const val ACTION_STOP = "dev.locus.test.action.STOP_RECOVERY"
    const val TAG = "LocusRecoveryTest"
}
