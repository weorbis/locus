package dev.locus.service

import android.annotation.TargetApi
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import dev.locus.receiver.NotificationActionReceiver

class ForegroundService : Service() {

    companion object {
        private const val TAG = "ForegroundService"
        private const val CHANNEL_ID = "foreground.service.channel"
        private const val DEFAULT_NOTIFICATION_ID = 197812504
        // Android's built-in star icon as fallback
        private const val FALLBACK_ICON = 17301514
    }

    @TargetApi(26)
    override fun onCreate() {
        super.onCreate()
        // Pre-create notification channel so it's ready before onStartCommand.
        // createNotificationChannel is idempotent — safe to call multiple times.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Background Services",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Enables background processing for motion detection."
        }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val extras = intent?.extras
        val notificationId = extras?.getInt("id", DEFAULT_NOTIFICATION_ID) ?: DEFAULT_NOTIFICATION_ID

        // Immediately promote to foreground with a minimal notification.
        // This MUST happen as fast as possible to avoid the 5-second
        // ForegroundServiceDidNotStartInTimeException on Android 14+.
        promoteToForeground(notificationId, buildMinimalNotification())

        if (extras != null) {
            try {
                // Build the full notification and update it in place.
                val fullNotification = buildFullNotification(extras)
                getSystemService(NotificationManager::class.java)
                    ?.notify(notificationId, fullNotification)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to build full notification, keeping minimal: ${e.message}")
                // Service is already in foreground with the minimal notification,
                // so the OS won't kill us.
            }
        } else {
            Log.e(TAG, "Attempted to start foreground service with null intent or extras.")
            stopSelf(startId)
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    @TargetApi(26)
    private fun buildMinimalNotification(): Notification {
        return Notification.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle("Starting...")
            .setOngoing(true)
            .setSmallIcon(FALLBACK_ICON)
            .build()
    }

    @TargetApi(26)
    private fun buildFullNotification(extras: Bundle): Notification {
        val context = applicationContext

        // Update notification channel importance if different from default
        val importanceValue = extras.getInt("importance", 1)
        val importance = when (importanceValue) {
            2 -> NotificationManager.IMPORTANCE_DEFAULT
            3 -> NotificationManager.IMPORTANCE_HIGH
            else -> NotificationManager.IMPORTANCE_LOW
        }
        if (importance != NotificationManager.IMPORTANCE_LOW) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Background Services",
                importance
            ).apply {
                description = "Enables background processing for motion detection."
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }

        // Resolve notification icon
        val iconName = extras.getString("icon")
        var icon = 0
        if (iconName != null) {
            icon = resources.getIdentifier(iconName, "drawable", context.packageName)
        }
        if (icon == 0) {
            icon = resources.getIdentifier("ic_launcher", "mipmap", context.packageName)
        }

        val builder = Notification.Builder(context, CHANNEL_ID)
            .setContentTitle(extras.getString("title"))
            .setContentText(extras.getString("text"))
            .setOngoing(true)
            .setSmallIcon(if (icon != 0) icon else FALLBACK_ICON)

        // Add notification actions if present
        extras.getStringArray("actions")?.filterNotNull()?.forEach { actionId ->
            val actionIntent = Intent(context, NotificationActionReceiver::class.java).apply {
                action = actionId
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                actionId.hashCode(),
                actionIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, actionId, pendingIntent)
        }

        return builder.build()
    }

    private fun promoteToForeground(id: Int, notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(id, notification)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
