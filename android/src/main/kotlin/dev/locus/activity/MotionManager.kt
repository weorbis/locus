package dev.locus.activity

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityRecognitionClient
import dev.locus.core.ConfigManager
import dev.locus.receiver.ActivityRecognizedBroadcastReceiver

class MotionManager(
    private val context: Context,
    private val config: ConfigManager
) {
    private val activityClient: ActivityRecognitionClient =
        ActivityRecognition.getClient(context)

    private val mainHandler = Handler(Looper.getMainLooper())

    private var activityPendingIntent: PendingIntent? = null
    private var stopTimeoutRunnable: Runnable? = null
    private var motionTriggerRunnable: Runnable? = null

    var lastActivityType: String = "unknown"
        private set

    var lastActivityConfidence: Int = 0
        private set

    var isMoving: Boolean = false
        private set

    private var listener: MotionListener? = null

    interface MotionListener {
        fun onMotionChange(isMoving: Boolean)
        fun onActivityChange(type: String, confidence: Int)
    }

    fun setListener(listener: MotionListener?) {
        this.listener = listener
    }

    fun start() {
        if (config.disableMotionActivityUpdates) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.ACTIVITY_RECOGNITION,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "Activity recognition permission not granted; motion updates disabled")
            return
        }

        val pendingIntent = createActivityPendingIntent()
        activityPendingIntent = pendingIntent

        activityClient.requestActivityUpdates(config.activityRecognitionInterval, pendingIntent)
            .addOnFailureListener { e ->
                Log.e(TAG, "Activity recognition failed: ${e.message}")
            }

        Log.i(TAG, "Activity recognition started")
    }

    fun stop() {
        cancelStopTimeout()
        cancelMotionTrigger()

        val pendingIntent = activityPendingIntent ?: return
        activityPendingIntent = null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.ACTIVITY_RECOGNITION,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            activityClient.removeActivityUpdates(pendingIntent)
        } else {
            Log.w(TAG, "Activity recognition permission revoked before cleanup")
        }
        Log.i(TAG, "Activity recognition stopped")
    }

    fun setPace(moving: Boolean) {
        setMovingState(moving)
    }

    fun onActivityEvent(type: String, confidence: Int) {
        if (confidence < config.minActivityConfidence) return

        lastActivityType = type
        lastActivityConfidence = confidence

        listener?.onActivityChange(type, confidence)

        val nextMoving = isMovingActivity(type)
        if (!nextMoving && config.disableStopDetection) return

        scheduleMotionTransition(nextMoving)
    }

    private fun scheduleMotionTransition(moving: Boolean) {
        if (moving) {
            cancelStopTimeout()
            cancelMotionTrigger()

            if (!isMoving) {
                if (config.motionTriggerDelay > 0) {
                    motionTriggerRunnable = Runnable { setMovingState(true) }
                    motionTriggerRunnable?.let { mainHandler.postDelayed(it, config.motionTriggerDelay) }
                } else {
                    setMovingState(true)
                }
            }
        } else {
            cancelMotionTrigger()

            when {
                config.stopTimeoutMinutes > 0 -> {
                    val delayMs = config.stopTimeoutMinutes * 60L * 1000L
                    scheduleStopTimeout(delayMs)
                }
                config.stopDetectionDelay > 0 -> {
                    scheduleStopTimeout(config.stopDetectionDelay)
                }
                else -> {
                    setMovingState(false)
                }
            }
        }
    }

    private fun setMovingState(moving: Boolean) {
        if (isMoving == moving) return

        isMoving = moving
        listener?.onMotionChange(moving)
    }

    private fun scheduleStopTimeout(delayMs: Long) {
        cancelStopTimeout()
        stopTimeoutRunnable = Runnable { setMovingState(false) }
        stopTimeoutRunnable?.let { mainHandler.postDelayed(it, delayMs) }
    }

    private fun cancelStopTimeout() {
        stopTimeoutRunnable?.let { runnable ->
            mainHandler.removeCallbacks(runnable)
            stopTimeoutRunnable = null
        }
    }

    private fun cancelMotionTrigger() {
        motionTriggerRunnable?.let { runnable ->
            mainHandler.removeCallbacks(runnable)
            motionTriggerRunnable = null
        }
    }

    private fun isMovingActivity(activityType: String): Boolean {
        if (config.triggerActivities.isNotEmpty()) {
            return activityType in config.triggerActivities
        }

        return activityType in MOVING_ACTIVITIES
    }

    private fun createActivityPendingIntent(): PendingIntent {
        val intent = Intent(context, ActivityRecognizedBroadcastReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Activity recognition must attach its result extras at delivery.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    companion object {
        private const val TAG = "locus.MotionManager"

        private val MOVING_ACTIVITIES = setOf(
            "walking",
            "running",
            "onFoot",
            "inVehicle",
            "onBicycle"
        )
    }
}
