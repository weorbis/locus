package dev.locus.receiver;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

import dev.locus.LocusPlugin;
import dev.locus.service.HeadlessService;

public class NotificationActionReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (action == null) {
            return;
        }
        SharedPreferences preferences =
                context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);
        preferences.edit()
                .putString(LocusPlugin.KEY_NOTIFICATION_ACTION, action)
                .apply();

        if (preferences.getBoolean("bg_enable_headless", false)) {
            long dispatcher = preferences.getLong("bg_headless_dispatcher", 0L);
            long callback = preferences.getLong("bg_headless_callback", 0L);
            if (dispatcher != 0L && callback != 0L) {
                try {
                    org.json.JSONObject eventPayload = new org.json.JSONObject();
                    eventPayload.put("type", "notificationaction");
                    eventPayload.put("data", action);
                    Intent headlessIntent = new Intent(context, HeadlessService.class);
                    headlessIntent.putExtra("dispatcher", dispatcher);
                    headlessIntent.putExtra("callback", callback);
                    headlessIntent.putExtra("event", eventPayload.toString());
                    HeadlessService.enqueueWork(context, headlessIntent);
                } catch (org.json.JSONException e) {
                    Log.w("NotificationAction", "Failed to build headless action payload", e);
                }
            }
        }
    }
}
