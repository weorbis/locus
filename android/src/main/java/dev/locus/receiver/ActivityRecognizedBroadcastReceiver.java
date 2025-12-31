package dev.locus.receiver;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

import com.google.android.gms.location.ActivityRecognitionResult;
import com.google.android.gms.location.DetectedActivity;

import java.util.List;

import dev.locus.LocusPlugin;
import dev.locus.service.HeadlessService;

public class ActivityRecognizedBroadcastReceiver extends BroadcastReceiver {

    private static final String TAG = "ActivityReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) {
            Log.w(TAG, "Received null intent");
            return;
        }

        ActivityRecognitionResult result = ActivityRecognitionResult.extractResult(intent);
        if (result == null) {
            Log.w(TAG, "ActivityRecognitionResult is null from intent");
            return;
        }

        List<DetectedActivity> activities = result.getProbableActivities();
        if (activities == null || activities.isEmpty()) {
            Log.w(TAG, "No detected activities available");
            return;
        }

        // Pick the most confident activity
        DetectedActivity mostLikely = activities.get(0);
        for (DetectedActivity a : activities) {
            if (a.getConfidence() > mostLikely.getConfidence()) {
                mostLikely = a;
            }
        }

        String type = getActivityString(mostLikely.getType());
        int confidence = mostLikely.getConfidence();
        String data = type + "," + confidence;

        Log.d(TAG, "Detected: " + data);

        // Forward to plugin via SharedPreferences
        SharedPreferences preferences =
                context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);

        preferences.edit()
                .putString(LocusPlugin.KEY_ACTIVITY_EVENT, data)
                .apply();

        if (preferences.getBoolean("bg_enable_headless", false)) {
            long dispatcher = preferences.getLong("bg_headless_dispatcher", 0L);
            long callback = preferences.getLong("bg_headless_callback", 0L);
            if (dispatcher != 0L && callback != 0L) {
                try {
                    org.json.JSONObject payload = new org.json.JSONObject();
                    org.json.JSONObject activity = new org.json.JSONObject();
                    activity.put("type", type);
                    activity.put("confidence", confidence);
                    payload.put("activity", activity);
                    org.json.JSONObject eventPayload = new org.json.JSONObject();
                    eventPayload.put("type", "activitychange");
                    eventPayload.put("data", payload);
                    Intent headlessIntent = new Intent(context, HeadlessService.class);
                    headlessIntent.putExtra("dispatcher", dispatcher);
                    headlessIntent.putExtra("callback", callback);
                    headlessIntent.putExtra("event", eventPayload.toString());
                    HeadlessService.enqueueWork(context, headlessIntent);
                } catch (org.json.JSONException e) {
                    Log.w(TAG, "Failed to build headless activity payload", e);
                }
            }
        }
    }

    private static String getActivityString(int type) {
        if (type == DetectedActivity.IN_VEHICLE) return "inVehicle";
        if (type == DetectedActivity.ON_BICYCLE) return "onBicycle";
        if (type == DetectedActivity.ON_FOOT) return "onFoot";
        if (type == DetectedActivity.RUNNING) return "running";
        if (type == DetectedActivity.STILL) return "still";
        if (type == DetectedActivity.TILTING) return "tilting";
        if (type == DetectedActivity.WALKING) return "walking";
        return "unknown";
    }
}
