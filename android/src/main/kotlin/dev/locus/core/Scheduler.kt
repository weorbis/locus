package dev.locus.core

import android.os.Handler
import android.os.Looper
import java.time.LocalTime

class Scheduler(
    private val config: ConfigManager,
    private val listener: SchedulerListener?
) {
    fun interface SchedulerListener {
        fun onScheduleCheck(shouldBeEnabled: Boolean): Boolean
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var scheduleRunnable: Runnable? = null
    private var checkIntervalMs = DEFAULT_CHECK_INTERVAL_MS

    fun start() {
        if (!config.scheduleEnabled || scheduleRunnable != null) {
            return
        }
        
        scheduleRunnable = object : Runnable {
            override fun run() {
                applyScheduleState()
                mainHandler.postDelayed(this, checkIntervalMs)
            }
        }.also { runnable ->
            mainHandler.post(runnable)
        }
    }

    fun stop() {
        scheduleRunnable?.let { runnable ->
            mainHandler.removeCallbacks(runnable)
            scheduleRunnable = null
        }
    }

    fun applyScheduleState() {
        if (!config.scheduleEnabled || config.schedule.isNullOrEmpty()) {
            return
        }
        val shouldEnable = isWithinScheduleWindow()
        listener?.onScheduleCheck(shouldEnable)
    }

    private fun isWithinScheduleWindow(): Boolean {
        val now = LocalTime.now()
        val nowMinutes = now.hour * 60 + now.minute
        val schedule = config.schedule ?: return false

        return schedule.any { entry ->
            entry?.let { parseScheduleEntry(it, nowMinutes) } ?: false
        }
    }

    private fun parseScheduleEntry(entry: String, nowMinutes: Int): Boolean {
        val parts = entry.split("-")
        if (parts.size != 2) return false

        val start = parseMinutes(parts[0]) ?: return false
        val end = parseMinutes(parts[1]) ?: return false

        return if (end < start) {
            // Window crosses midnight
            nowMinutes >= start || nowMinutes < end
        } else {
            nowMinutes >= start && nowMinutes < end
        }
    }

    private fun parseMinutes(time: String): Int? {
        return try {
            val parts = time.split(":")
            if (parts.size == 2) {
                parts[0].toInt() * 60 + parts[1].toInt()
            } else {
                null
            }
        } catch (e: NumberFormatException) {
            null
        }
    }

    companion object {
        private const val DEFAULT_CHECK_INTERVAL_MS = 60000L
    }
}
