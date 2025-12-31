package dev.locus.core;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import org.json.JSONObject;

import java.util.Map;

import dev.locus.service.HeadlessService;

public class HeadlessDispatcher {
    private final Context context;
    private final ConfigManager config;
    private final SharedPreferences prefs;

    public HeadlessDispatcher(Context context, ConfigManager config, SharedPreferences prefs) {
        this.context = context;
        this.config = config;
        this.prefs = prefs;
    }

    public void dispatch(Map<String, Object> event) {
        if (!config.enableHeadless || prefs == null) {
            return;
        }
        long dispatcher = prefs.getLong("bg_headless_dispatcher", 0L);
        long callback = prefs.getLong("bg_headless_callback", 0L);
        if (dispatcher == 0L || callback == 0L) {
            return;
        }
        try {
            JSONObject payload = new JSONObject(event);
            Intent intent = new Intent(context, HeadlessService.class);
            intent.putExtra("dispatcher", dispatcher);
            intent.putExtra("callback", callback);
            intent.putExtra("event", payload.toString());
            HeadlessService.enqueueWork(context, intent);
        } catch (Exception ignored) {
        }
    }
}
