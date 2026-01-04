package dev.locus.receiver;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

import com.google.android.gms.location.Geofence;
import com.google.android.gms.location.GeofencingEvent;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

import dev.locus.LocusPlugin;
import dev.locus.service.HeadlessService;

public class GeofenceBroadcastReceiver extends BroadcastReceiver {
    private static final String TAG = "GeofenceReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        GeofencingEvent event = GeofencingEvent.fromIntent(intent);
        if (event == null) {
            Log.w(TAG, "GeofencingEvent is null");
            return;
        }
        if (event.hasError()) {
            Log.w(TAG, "GeofencingEvent error: " + event.getErrorCode());
            return;
        }

        int transition = event.getGeofenceTransition();
        String action = "unknown";
        if (transition == Geofence.GEOFENCE_TRANSITION_ENTER) {
            action = "enter";
        } else if (transition == Geofence.GEOFENCE_TRANSITION_EXIT) {
            action = "exit";
        } else if (transition == Geofence.GEOFENCE_TRANSITION_DWELL) {
            action = "dwell";
        }

        List<String> ids = new ArrayList<>();
        for (Geofence geofence : event.getTriggeringGeofences()) {
            ids.add(geofence.getRequestId());
        }

        JSONObject payload = new JSONObject();
        try {
            payload.put("action", action);
            payload.put("identifiers", ids);
            if (event.getTriggeringLocation() != null) {
                JSONObject location = new JSONObject();
                location.put("latitude", event.getTriggeringLocation().getLatitude());
                location.put("longitude", event.getTriggeringLocation().getLongitude());
                location.put("accuracy", event.getTriggeringLocation().getAccuracy());
                payload.put("location", location);
            }
        } catch (JSONException e) {
            Log.e(TAG, "Failed to encode geofence event", e);
        }

        SharedPreferences preferences =
                context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);

        if (preferences.getBoolean("bg_privacy_mode", false)) {
            return;
        }

        preferences.edit()
                .putString(LocusPlugin.KEY_GEOFENCE_EVENT, payload.toString())
                .apply();

        if (preferences.getBoolean("bg_enable_headless", false)) {
            long dispatcher = preferences.getLong("bg_headless_dispatcher", 0L);
            long callback = preferences.getLong("bg_headless_callback", 0L);
            if (dispatcher != 0L && callback != 0L) {
                JSONObject eventPayload = new JSONObject();
                try {
                    eventPayload.put("type", "geofence");
                    eventPayload.put("data", payload);
                } catch (JSONException e) {
                    Log.w(TAG, "Failed to wrap geofence event for headless", e);
                }
                Intent headlessIntent = new Intent(context, HeadlessService.class);
                headlessIntent.putExtra("dispatcher", dispatcher);
                headlessIntent.putExtra("callback", callback);
                headlessIntent.putExtra("event", eventPayload.toString());
                HeadlessService.enqueueWork(context, headlessIntent);
            }
        }
    }
}
