package dev.locus.core;

import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.locus.activity.MotionManager;
import dev.locus.geofence.GeofenceManager;

public class PreferenceEventHandler {
    private static final String TAG = "locus";
    private static final String KEY_ACTIVITY_EVENT = "bg_activity_event";
    private static final String KEY_GEOFENCE_EVENT = "bg_geofence_event";
    private static final String KEY_NOTIFICATION_ACTION = "bg_notification_action";

    private final ConfigManager config;
    private final MotionManager motionManager;
    private final GeofenceManager geofenceManager;
    private final StateManager stateManager;
    private final SyncManager syncManager;
    private final EventDispatcher eventDispatcher;
    private final LocationTracker.AutoSyncChecker autoSyncChecker;

    public PreferenceEventHandler(ConfigManager config,
                                  MotionManager motionManager,
                                  GeofenceManager geofenceManager,
                                  StateManager stateManager,
                                  SyncManager syncManager,
                                  EventDispatcher eventDispatcher,
                                  LocationTracker.AutoSyncChecker autoSyncChecker) {
        this.config = config;
        this.motionManager = motionManager;
        this.geofenceManager = geofenceManager;
        this.stateManager = stateManager;
        this.syncManager = syncManager;
        this.eventDispatcher = eventDispatcher;
        this.autoSyncChecker = autoSyncChecker;
    }

    public void handlePreferenceChange(SharedPreferences sharedPreferences, String key) {
        if (KEY_ACTIVITY_EVENT.equals(key)) {
            if (config.disableMotionActivityUpdates) {
                return;
            }
            String raw = sharedPreferences.getString(KEY_ACTIVITY_EVENT, null);
            if (raw != null) {
                String[] tokens = raw.split(",");
                if (tokens.length >= 2) {
                    try {
                        String type = tokens[0];
                        int confidence = Integer.parseInt(tokens[1]);
                        motionManager.onActivityEvent(type, confidence);
                    } catch (NumberFormatException e) {
                        Log.w(TAG, "Invalid activity event format: " + raw);
                    }
                }
            }
        } else if (KEY_GEOFENCE_EVENT.equals(key)) {
            String raw = sharedPreferences.getString(KEY_GEOFENCE_EVENT, null);
            if (raw != null) {
                try {
                    JSONObject obj = new JSONObject(raw);
                    Map<String, Object> geofenceEvent = buildGeofenceEvent(obj);
                    if (geofenceEvent != null) {
                        Map<String, Object> data = asMap(geofenceEvent.get("data"));
                        if (data != null && data.get("location") instanceof Map) {
                            Map<String, Object> locationPayload = asMap(data.get("location"));
                            if (PersistencePolicy.shouldPersist(config, "geofence")) {
                                stateManager.storeLocationPayload(locationPayload, config.maxDaysToPersist, config.maxRecordsToPersist);
                            }
                            if (config.autoSync && config.httpUrl != null && !config.httpUrl.isEmpty() && autoSyncChecker.isAutoSyncAllowed()) {
                                if (config.batchSync) {
                                    syncManager.attemptBatchSync();
                                } else {
                                    syncManager.syncNow(locationPayload);
                                }
                            }
                        }
                        eventDispatcher.sendEvent(geofenceEvent);
                    }
                } catch (JSONException e) {
                    Log.e(TAG, "Failed to parse geofence event: " + e.getMessage());
                }
            }
        } else if (KEY_NOTIFICATION_ACTION.equals(key)) {
            String action = sharedPreferences.getString(KEY_NOTIFICATION_ACTION, null);
            if (action != null) {
                Map<String, Object> event = new HashMap<>();
                event.put("type", "notificationaction");
                event.put("data", action);
                eventDispatcher.sendEvent(event);
            }
        }
    }

    private Map<String, Object> buildGeofenceEvent(JSONObject obj) throws JSONException {
        String action = obj.optString("action", "unknown");
        List<String> identifiers = new ArrayList<>();
        JSONArray ids = obj.optJSONArray("identifiers");
        if (ids != null) {
            for (int i = 0; i < ids.length(); i++) {
                identifiers.add(ids.optString(i));
            }
        }

        Map<String, Object> geofenceData = null;
        if (!identifiers.isEmpty()) {
            geofenceData = geofenceManager.getGeofenceSync(identifiers.get(0));
        }
        if (geofenceData == null) {
            geofenceData = new HashMap<>();
            geofenceData.put("identifier", identifiers.isEmpty() ? "unknown" : identifiers.get(0));
        }

        Map<String, Object> location = null;
        if (obj.has("location")) {
            JSONObject loc = obj.optJSONObject("location");
            if (loc != null) {
                location = new HashMap<>();
                location.put("uuid", UUID.randomUUID().toString());
                location.put("timestamp", Instant.now().toString());
                location.put("coords", toMap(loc));
                location.put("event", "geofence");
                location.put("is_moving", motionManager.isMoving());
            }
        }

        Map<String, Object> payload = new HashMap<>();
        payload.put("geofence", geofenceData);
        payload.put("action", action);
        if (location != null) {
            payload.put("location", location);
        }

        Map<String, Object> event = new HashMap<>();
        event.put("type", "geofence");
        event.put("data", payload);
        return event;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> asMap(Object value) {
        if (value instanceof Map) {
            return (Map<String, Object>) value;
        }
        return null;
    }

    private Map<String, Object> toMap(JSONObject obj) throws JSONException {
        Map<String, Object> map = new HashMap<>();
        java.util.Iterator<String> keys = obj.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            Object value = obj.get(key);
            map.put(key, value);
        }
        return map;
    }
}
