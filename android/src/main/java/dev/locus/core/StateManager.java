package dev.locus.core;

import android.content.Context;
import android.content.SharedPreferences;
import android.location.Location;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.locus.LocusPlugin;
import dev.locus.location.Odometer;
import dev.locus.storage.LocationStore;
import dev.locus.storage.LogStore;
import dev.locus.storage.QueueStore;

public class StateManager {

    private static final String KEY_TRIP_STATE = "bg_trip_state";

    private final SharedPreferences prefs;
    private final LocationStore locationStore;
    private final QueueStore queueStore;
    private final LogStore logStore;
    private final Odometer odometer;

    public StateManager(Context context) {
        this.prefs = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);
        this.locationStore = new LocationStore(context);
        this.queueStore = new QueueStore(context);
        this.logStore = new LogStore(context);
        this.odometer = new Odometer(context);
    }

    public LocationStore getLocationStore() {
        return locationStore;
    }

    public QueueStore getQueueStore() {
        return queueStore;
    }

    public LogStore getLogStore() {
        return logStore;
    }

    public Odometer getOdometer() {
        return odometer;
    }

    public double getOdometerValue() {
        return odometer.getDistance();
    }

    public void setOdometer(double value) {
        odometer.setDistance(value);
    }

    public void updateOdometer(Location location) {
        odometer.update(location);
    }

    public void clearLocations() {
        locationStore.clear();
    }

    public List<Map<String, Object>> getStoredLocations(int limit) {
        List<Map<String, Object>> records = locationStore.readLocations(limit);
        List<Map<String, Object>> payloads = new ArrayList<>();
        for (Map<String, Object> record : records) {
            Map<String, Object> payload = buildPayloadFromRecord(record);
            if (!payload.isEmpty()) {
                payloads.add(payload);
            }
        }
        return payloads;
    }

    public void storeLocationPayload(Map<String, Object> payload, int maxDays, int maxRecords) {
        locationStore.insertPayload(payload, maxDays, maxRecords);
    }

    public String enqueue(Map<String, Object> payload, String type, String idempotencyKey, int maxDays, int maxRecords) {
        return queueStore.insertPayload(payload, type, idempotencyKey, maxDays, maxRecords);
    }

    public List<Map<String, Object>> getQueue(int limit) {
        return buildQueuePayload(queueStore.readQueue(limit));
    }

    public void clearQueue() {
        queueStore.clear();
    }

    public void appendLog(String level, String message, int maxDays) {
        logStore.append(level, message, maxDays);
    }

    public List<Map<String, Object>> readLogEntries(int limit) {
        return logStore.readEntries(limit);
    }

    public void storeTripState(Map<String, Object> tripState) {
        prefs.edit().putString(KEY_TRIP_STATE, new JSONObject(tripState).toString()).apply();
    }

    public Map<String, Object> readTripState() {
        String tripJson = prefs.getString(KEY_TRIP_STATE, null);
        if (tripJson == null) {
            return null;
        }
        try {
            JSONObject json = new JSONObject(tripJson);
            return toMap(json);
        } catch (JSONException e) {
            return null;
        }
    }

    public void clearTripState() {
        prefs.edit().remove(KEY_TRIP_STATE).apply();
    }

    private Map<String, Object> buildPayloadFromRecord(Map<String, Object> record) {
        if (record == null) {
            return new HashMap<>();
        }
        Map<String, Object> payload = new HashMap<>();
        Object id = record.get("id");
        Object timestampValue = record.get("timestamp");
        Object latitudeValue = record.get("latitude");
        Object longitudeValue = record.get("longitude");
        Object accuracyValue = record.get("accuracy");
        Object speedValue = record.get("speed");
        Object headingValue = record.get("heading");
        Object altitudeValue = record.get("altitude");
        
        double latitude = latitudeValue instanceof Number ? ((Number) latitudeValue).doubleValue() : 0.0;
        double longitude = longitudeValue instanceof Number ? ((Number) longitudeValue).doubleValue() : 0.0;
        double accuracy = accuracyValue instanceof Number ? ((Number) accuracyValue).doubleValue() : 0.0;
        double speed = speedValue instanceof Number ? ((Number) speedValue).doubleValue() : 0.0;
        double heading = headingValue instanceof Number ? ((Number) headingValue).doubleValue() : 0.0;
        double altitude = altitudeValue instanceof Number ? ((Number) altitudeValue).doubleValue() : 0.0;
        
        Map<String, Object> coords = new HashMap<>();
        coords.put("latitude", latitude);
        coords.put("longitude", longitude);
        coords.put("accuracy", accuracy);
        coords.put("speed", speed);
        coords.put("heading", heading);
        coords.put("altitude", altitude);

        Map<String, Object> activity = new HashMap<>();
        Object activityType = record.get("activity_type");
        if (activityType instanceof String) {
            activity.put("type", activityType);
        }
        Object activityConfidence = record.get("activity_confidence");
        if (activityConfidence instanceof Number) {
            activity.put("confidence", ((Number) activityConfidence).intValue());
        }

        payload.put("uuid", id instanceof String ? id : UUID.randomUUID().toString());
        long timestamp = timestampValue instanceof Number ? ((Number) timestampValue).longValue() : System.currentTimeMillis();
        payload.put("timestamp", Instant.ofEpochMilli(timestamp).toString());
        payload.put("coords", coords);
        if (!activity.isEmpty()) {
            payload.put("activity", activity);
        }
        payload.put("event", record.get("event"));
        payload.put("is_moving", record.get("is_moving"));
        if (record.get("odometer") != null) {
            payload.put("odometer", record.get("odometer"));
        }
        return payload;
    }

    private List<Map<String, Object>> buildQueuePayload(List<Map<String, Object>> records) {
        List<Map<String, Object>> items = new ArrayList<>();
        for (Map<String, Object> record : records) {
            Map<String, Object> item = new HashMap<>();
            item.put("id", record.get("id"));
            Object createdAt = record.get("createdAt");
            if (createdAt instanceof Number) {
                item.put("createdAt", Instant.ofEpochMilli(((Number) createdAt).longValue()).toString());
            }
            Object retryCount = record.get("retryCount");
            if (retryCount instanceof Number) {
                item.put("retryCount", ((Number) retryCount).intValue());
            }
            Object nextRetryAt = record.get("nextRetryAt");
            if (nextRetryAt instanceof Number) {
                item.put("nextRetryAt", Instant.ofEpochMilli(((Number) nextRetryAt).longValue()).toString());
            }
            Object idempotencyKey = record.get("idempotencyKey");
            if (idempotencyKey instanceof String) {
                item.put("idempotencyKey", idempotencyKey);
            }
            Object type = record.get("type");
            if (type instanceof String) {
                item.put("type", type);
            }
            Object payloadJson = record.get("payload");
            if (payloadJson instanceof String) {
                try {
                    item.put("payload", QueueStore.parsePayload((String) payloadJson));
                } catch (JSONException ignored) {
                }
            }
            items.add(item);
        }
        return items;
    }

    private Map<String, Object> toMap(JSONObject obj) throws JSONException {
        Map<String, Object> map = new HashMap<>();
        JSONArray names = obj.names();
        if (names == null) {
            return map;
        }
        for (int i = 0; i < names.length(); i++) {
            String key = names.optString(i);
            Object value = obj.opt(key);
            if (value instanceof JSONObject) {
                map.put(key, toMap((JSONObject) value));
            } else if (value instanceof JSONArray) {
                map.put(key, toList((JSONArray) value));
            } else if (value == JSONObject.NULL) {
                map.put(key, null);
            } else {
                map.put(key, value);
            }
        }
        return map;
    }

    private List<Object> toList(JSONArray array) throws JSONException {
        List<Object> list = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            Object value = array.opt(i);
            if (value instanceof JSONObject) {
                list.add(toMap((JSONObject) value));
            } else if (value instanceof JSONArray) {
                list.add(toList((JSONArray) value));
            } else if (value == JSONObject.NULL) {
                list.add(null);
            } else {
                list.add(value);
            }
        }
        return list;
    }
}
