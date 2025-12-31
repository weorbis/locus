package dev.locus.core;

import android.content.Context;
import android.content.Intent;

import dev.locus.service.ForegroundService;

public class ForegroundServiceController {
    private final Context context;

    public ForegroundServiceController(Context context) {
        this.context = context;
    }

    public void start(ConfigManager config) {
        Intent intent = new Intent(context, ForegroundService.class);
        intent.putExtra("title", config.notificationTitle)
                .putExtra("text", config.notificationText)
                .putExtra("icon", config.notificationIcon)
                .putExtra("id", config.notificationId)
                .putExtra("importance", config.notificationImportance);
        if (config.notificationActions != null && !config.notificationActions.isEmpty()) {
            intent.putExtra("actions", config.notificationActions.toArray(new String[0]));
        }
        context.startForegroundService(intent);
    }

    public void stop() {
        Intent intent = new Intent(context, ForegroundService.class);
        context.stopService(intent);
    }
}
