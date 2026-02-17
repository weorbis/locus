package dev.locus.location

import android.content.Context
import android.content.SharedPreferences
import android.location.Location
import dev.locus.LocusPlugin

class Odometer(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE)

    private var odometer: Double = readOdometer()
    private var lastLocation: Location? = null

    val distance: Double
        get() = odometer

    @Synchronized
    fun update(newLocation: Location) {
        val last = lastLocation
        if (last == null) {
            lastLocation = newLocation
            return
        }

        val distance = newLocation.distanceTo(last)
        // Basic filter: ignore huge jumps > 100km or tiny < 1m if needed,
        // but for now let's just accumulate.
        odometer += distance
        lastLocation = newLocation
        writeOdometer(odometer)
    }

    fun setDistance(distance: Double) {
        odometer = distance
        writeOdometer(distance)
        // Reset last location reference to avoid adding distance from a discontinuity
        lastLocation = null
    }

    private fun readOdometer(): Double {
        // Migration: prefer 64-bit long storage, fall back to legacy 32-bit float
        if (prefs.contains(KEY_ODOMETER_LONG)) {
            return Double.fromBits(prefs.getLong(KEY_ODOMETER_LONG, 0L))
        }
        val legacy = prefs.getFloat(KEY_ODOMETER, 0.0f).toDouble()
        if (legacy > 0) writeOdometer(legacy) // migrate to long storage
        return legacy
    }

    private fun writeOdometer(value: Double) {
        prefs.edit().putLong(KEY_ODOMETER_LONG, value.toBits()).apply()
    }

    companion object {
        private const val KEY_ODOMETER = "bg_odometer"
        private const val KEY_ODOMETER_LONG = "bg_odometer_long"
    }
}
