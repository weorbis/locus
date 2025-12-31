package dev.locus.service;

import android.content.Intent;
import android.content.Context;
import android.app.Service;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.os.IBinder;
import android.os.Bundle;
import android.annotation.TargetApi;
import android.util.Log;
import android.app.PendingIntent;
import android.content.Intent;

import dev.locus.receiver.NotificationActionReceiver;

public class ForegroundService extends Service {
    private final String TAG = "ForegroundService";

    public ForegroundService() {
        super();
    }

    @Override
    public void onCreate() {
        super.onCreate();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && intent.getExtras() != null) {
            startPluginForegroundService(intent.getExtras());
        } else {
            Log.e(TAG, "Attempted to start foreground service with null intent or extras.");
        }
        return START_STICKY;
    }

    @TargetApi(26)
    private void startPluginForegroundService(Bundle extras) {
        Context context = getApplicationContext();
        String channelId = "foreground.service.channel";

        // Get notification channel importance
        int importanceValue = extras.getInt("importance", 1);
        int importance;
        switch (importanceValue) {
            case 2:
                importance = NotificationManager.IMPORTANCE_DEFAULT;
                break;
            case 3:
                importance = NotificationManager.IMPORTANCE_HIGH;
                break;
            default:
                importance = NotificationManager.IMPORTANCE_LOW;
        }

        // Create notification channel
        NotificationChannel channel = new NotificationChannel(channelId, "Background Services", importance);
        channel.setDescription("Enables background processing for motion detection.");
        getSystemService(NotificationManager.class).createNotificationChannel(channel);

        // Get notification icon
        String iconName = extras.getString("icon");
        int icon = 0;
        if (iconName != null) {
            icon = getResources().getIdentifier(iconName, "drawable", context.getPackageName());
        }
        if (icon == 0) {
            icon = getResources().getIdentifier("ic_launcher", "mipmap", context.getPackageName());
        }

        Notification.Builder builder = new Notification.Builder(context, channelId)
                .setContentTitle(extras.getString("title"))
                .setContentText(extras.getString("text"))
                .setOngoing(true)
                .setSmallIcon(icon != 0 ? icon : 17301514); // Default is the star icon

        if (extras.containsKey("actions")) {
            String[] actions = extras.getStringArray("actions");
            if (actions != null) {
                for (String actionId : actions) {
                    Intent actionIntent = new Intent(context, NotificationActionReceiver.class);
                    actionIntent.setAction(actionId);
                    PendingIntent pendingIntent = PendingIntent.getBroadcast(
                            context,
                            actionId.hashCode(),
                            actionIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
                    );
                    builder.addAction(0, actionId, pendingIntent);
                }
            }
        }

        Notification notification = builder.build();

        int id = extras.getInt("id", 197812504);

        // Put service in foreground and show notification
        startForeground(id, notification);
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
