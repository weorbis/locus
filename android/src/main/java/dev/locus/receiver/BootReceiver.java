package dev.locus.receiver;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import dev.locus.LocusPlugin;
import dev.locus.service.HeadlessService;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) {
            return;
        }
        String action = intent.getAction();
        if (action == null) {
            return;
        }
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !"android.intent.action.QUICKBOOT_POWERON".equals(action)
                && !"com.htc.intent.action.QUICKBOOT_POWERON".equals(action)) {
            return;
        }

        SharedPreferences prefs = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);
        boolean startOnBoot = prefs.getBoolean("bg_start_on_boot", false);
        boolean headlessEnabled = prefs.getBoolean("bg_enable_headless", false);
        if (!startOnBoot || !headlessEnabled) {
            return;
        }
        long dispatcher = prefs.getLong("bg_headless_dispatcher", 0L);
        long callback = prefs.getLong("bg_headless_callback", 0L);
        if (dispatcher == 0L || callback == 0L) {
            return;
        }

        Intent serviceIntent = new Intent(context, HeadlessService.class);
        serviceIntent.putExtra("dispatcher", dispatcher);
        serviceIntent.putExtra("callback", callback);
        serviceIntent.putExtra("event", "{\"type\":\"boot\"}");
        HeadlessService.enqueueWork(context, serviceIntent);
    }
}
