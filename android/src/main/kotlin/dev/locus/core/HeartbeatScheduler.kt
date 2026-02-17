package dev.locus.core

import android.os.Handler
import android.os.Looper

class HeartbeatScheduler(
    private val handler: Handler = Handler(Looper.getMainLooper())
) {
    private var heartbeatRunnable: Runnable? = null

    fun start(intervalSeconds: Int, onHeartbeat: () -> Unit) {
        if (intervalSeconds <= 0 || heartbeatRunnable != null) {
            return
        }

        heartbeatRunnable = object : Runnable {
            override fun run() {
                onHeartbeat()
                handler.postDelayed(this, intervalSeconds * 1000L)
            }
        }.also { runnable ->
            handler.post(runnable) // Fire first heartbeat immediately
        }
    }

    fun stop() {
        heartbeatRunnable?.let { runnable ->
            handler.removeCallbacks(runnable)
            heartbeatRunnable = null
        }
    }

    fun restart(intervalSeconds: Int, onHeartbeat: () -> Unit) {
        stop()
        start(intervalSeconds, onHeartbeat)
    }
}
