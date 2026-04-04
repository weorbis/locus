package dev.locus.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import dev.locus.LocusPlugin
import dev.locus.service.HeadlessService

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        val action = intent.action ?: return

        // Check for various boot completed actions
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        val prefs = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE)

        val startOnBoot = prefs.getBoolean("bg_start_on_boot", false)
        val headlessEnabled = prefs.getBoolean("bg_enable_headless", false)
        if (!startOnBoot || !headlessEnabled) {
            return
        }

        val dispatcher = prefs.getLong("bg_headless_dispatcher", 0L)
        val callback = prefs.getLong("bg_headless_callback", 0L)
        if (dispatcher == 0L || callback == 0L) {
            return
        }

        // Verify location permission before dispatching headless service.
        // On Android 14+ (SDK 34+), starting a foreground service with type
        // "location" without the runtime permission throws SecurityException.
        val hasLocationPermission = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasLocationPermission) {
            Log.w("BootReceiver", "Skipping headless dispatch: ACCESS_FINE_LOCATION not granted")
            return
        }

        val serviceIntent = Intent(context, HeadlessService::class.java).apply {
            putExtra("dispatcher", dispatcher)
            putExtra("callback", callback)
            putExtra("event", "{\"type\":\"boot\"}")
        }
        HeadlessService.enqueueWork(context, serviceIntent)
    }
}
