package dev.locus.geofence;

import android.annotation.SuppressLint;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import com.google.android.gms.location.Geofence;
import com.google.android.gms.location.GeofencingClient;
import com.google.android.gms.location.GeofencingRequest;
import com.google.android.gms.location.LocationServices;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import dev.locus.LocusPlugin;
import dev.locus.receiver.GeofenceBroadcastReceiver;
import io.flutter.plugin.common.MethodChannel;

public class GeofenceManager {


    private static final String KEY_GEOFENCE_STORE = "bg_geofences";

    private final Context context;
    private final GeofencingClient geofencingClient;
    private final SharedPreferences prefs;
    private final GeofenceListener listener;
    private int maxMonitoredGeofences = 0;
    private PendingIntent geofencePendingIntent;

    public interface GeofenceListener {
        void onGeofencesChanged(List<String> addedIds, List<String> removedIds);
    }

    public GeofenceManager(Context context, GeofenceListener listener) {
        this.context = context;
        this.listener = listener;
        this.geofencingClient = LocationServices.getGeofencingClient(context);
        this.prefs = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);
    }

    public void setMaxMonitoredGeofences(int max) {
        this.maxMonitoredGeofences = max;
    }

    @SuppressLint("MissingPermission")
    public void addGeofence(Map<String, Object> geofenceMap, MethodChannel.Result result) {
        try {
            Geofence geofence = buildGeofence(geofenceMap);
            String identifier = geofenceMap.get("identifier") instanceof String
                    ? (String) geofenceMap.get("identifier")
                    : null;
            List<Geofence> geofences = new ArrayList<>();
            geofences.add(geofence);
            GeofencingRequest request = new GeofencingRequest.Builder()
                    .setInitialTrigger(geofenceMap.containsKey("notifyOnEntry") && Boolean.TRUE.equals(geofenceMap.get("notifyOnEntry"))
                            ? GeofencingRequest.INITIAL_TRIGGER_ENTER
                            : 0)
                    .addGeofence(geofence)
                    .build();
            geofencePendingIntent = createGeofencePendingIntent();

            geofencingClient.addGeofences(request, geofencePendingIntent)
                    .addOnSuccessListener(unused -> {
                        storeGeofence(geofenceMap);
                        enforceMaxMonitoredGeofences();
                        if (identifier != null) {
                            List<String> added = new ArrayList<>();
                            added.add(identifier);
                            if (listener != null) listener.onGeofencesChanged(added, new ArrayList<>());
                        }
                        result.success(true);
                    })
                    .addOnFailureListener(e -> result.error("GEOFENCE_ERROR", e.getMessage(), null));
        } catch (Exception e) {
            result.error("GEOFENCE_ERROR", e.getMessage(), null);
        }
    }

    @SuppressLint("MissingPermission")
    public void addGeofences(List<Object> geofences, MethodChannel.Result result) {
        try {
            List<Geofence> geofenceList = new ArrayList<>();
            JSONArray stored = readGeofenceStore();
            List<String> addedIds = new ArrayList<>();
            for (Object obj : geofences) {
                Map<String, Object> map = asMap(obj);
                if (map == null) {
                    continue;
                }
                geofenceList.add(buildGeofence(map));
                Object identifier = map.get("identifier");
                if (identifier instanceof String) {
                    addedIds.add((String) identifier);
                }
                stored.put(new JSONObject(map));
            }
            GeofencingRequest request = new GeofencingRequest.Builder()
                    .addGeofences(geofenceList)
                    .build();
            geofencePendingIntent = createGeofencePendingIntent();
            geofencingClient.addGeofences(request, geofencePendingIntent)
                    .addOnSuccessListener(unused -> {
                        writeGeofenceStore(stored);
                        enforceMaxMonitoredGeofences();
                        if (!addedIds.isEmpty()) {
                            if (listener != null) listener.onGeofencesChanged(addedIds, new ArrayList<>());
                        }
                        result.success(true);
                    })
                    .addOnFailureListener(e -> result.error("GEOFENCE_ERROR", e.getMessage(), null));
        } catch (Exception e) {
            result.error("GEOFENCE_ERROR", e.getMessage(), null);
        }
    }

    public void removeGeofence(Object identifier, MethodChannel.Result result) {
        if (!(identifier instanceof String)) {
            result.error("INVALID_ARGUMENT", "Expected geofence identifier string", null);
            return;
        }
        List<String> ids = new ArrayList<>();
        ids.add((String) identifier);
        geofencingClient.removeGeofences(ids)
                .addOnSuccessListener(unused -> {
                    removeGeofenceFromStore((String) identifier);
                    if (listener != null) listener.onGeofencesChanged(new ArrayList<>(), ids);
                    result.success(true);
                })
                .addOnFailureListener(e -> result.error("GEOFENCE_ERROR", e.getMessage(), null));
    }

    public void removeGeofences(MethodChannel.Result result) {
        JSONArray stored = readGeofenceStore();
        List<String> removedIds = extractIdentifiers(stored);
        geofencingClient.removeGeofences(createGeofencePendingIntent())
                .addOnSuccessListener(unused -> {
                    writeGeofenceStore(new JSONArray());
                    if (!removedIds.isEmpty()) {
                        if (listener != null) listener.onGeofencesChanged(new ArrayList<>(), removedIds);
                    }
                    result.success(true);
                })
                .addOnFailureListener(e -> result.error("GEOFENCE_ERROR", e.getMessage(), null));
    }

    public void getGeofence(Object identifier, MethodChannel.Result result) {
        if (!(identifier instanceof String)) {
            result.success(null);
            return;
        }
        result.success(getGeofenceSync((String) identifier));
    }

    public Map<String, Object> getGeofenceSync(String identifier) {
        JSONArray array = readGeofenceStore();
        for (int i = 0; i < array.length(); i++) {
            JSONObject obj = array.optJSONObject(i);
            if (obj != null && identifier.equals(obj.optString("identifier"))) {
                try {
                    return toMap(obj);
                } catch (JSONException e) {
                    return null;
                }
            }
        }
        return null;
    }

    public void getGeofences(MethodChannel.Result result) {
        JSONArray array = readGeofenceStore();
        List<Map<String, Object>> list = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            JSONObject obj = array.optJSONObject(i);
            if (obj != null) {
                try {
                    list.add(toMap(obj));
                } catch (JSONException e) {
                    // ignore malformed entries
                }
            }
        }
        result.success(list);
    }

    public void geofenceExists(Object identifier, MethodChannel.Result result) {
        if (!(identifier instanceof String)) {
            result.error("INVALID_ARGUMENT", "Expected geofence identifier string", null);
            return;
        }
        JSONArray array = readGeofenceStore();
        for (int i = 0; i < array.length(); i++) {
            JSONObject obj = array.optJSONObject(i);
            if (obj != null && identifier.equals(obj.optString("identifier"))) {
                result.success(true);
                return;
            }
        }
        result.success(false);
    }

    public void startGeofences(MethodChannel.Result result) {
        startGeofencesInternal();
        result.success(true);
    }

    @SuppressLint("MissingPermission")
    public void startGeofencesInternal() {
        JSONArray stored = readGeofenceStore();
        if (maxMonitoredGeofences > 0 && stored.length() > maxMonitoredGeofences) {
            trimGeofenceStore(stored, stored.length() - maxMonitoredGeofences);
            stored = readGeofenceStore();
        }
        if (stored.length() == 0) {
            return;
        }
        List<Geofence> geofences = new ArrayList<>();
        for (int i = 0; i < stored.length(); i++) {
            JSONObject obj = stored.optJSONObject(i);
            if (obj != null) {
                try {
                    geofences.add(buildGeofence(toMap(obj)));
                } catch (JSONException e) {
                   // Ignore malformed
                }
            }
        }
        if (geofences.isEmpty()) return;
        
        GeofencingRequest request = new GeofencingRequest.Builder()
                .addGeofences(geofences)
                .build();
        geofencePendingIntent = createGeofencePendingIntent();
        geofencingClient.addGeofences(request, geofencePendingIntent);
    }

    private Geofence buildGeofence(Map<String, Object> map) {
        Object identifierObj = map.get("identifier");
        Object radiusObj = map.get("radius");
        Object latObj = map.get("latitude");
        Object lonObj = map.get("longitude");

        if (!(identifierObj instanceof String)) {
            throw new IllegalArgumentException("Geofence 'identifier' is required and must be a String");
        }
        if (!(radiusObj instanceof Number)) {
            throw new IllegalArgumentException("Geofence 'radius' is required and must be a Number");
        }
        if (!(latObj instanceof Number)) {
            throw new IllegalArgumentException("Geofence 'latitude' is required and must be a Number");
        }
        if (!(lonObj instanceof Number)) {
            throw new IllegalArgumentException("Geofence 'longitude' is required and must be a Number");
        }

        String identifier = (String) identifierObj;
        double radius = ((Number) radiusObj).doubleValue();
        double lat = ((Number) latObj).doubleValue();
        double lon = ((Number) lonObj).doubleValue();

        boolean notifyOnEntry = map.get("notifyOnEntry") == null || Boolean.TRUE.equals(map.get("notifyOnEntry"));
        boolean notifyOnExit = map.get("notifyOnExit") == null || Boolean.TRUE.equals(map.get("notifyOnExit"));
        boolean notifyOnDwell = Boolean.TRUE.equals(map.get("notifyOnDwell"));
        int loiteringDelay = map.get("loiteringDelay") instanceof Number ? ((Number) map.get("loiteringDelay")).intValue() : 0;

        int transitionTypes = 0;
        if (notifyOnEntry) transitionTypes |= Geofence.GEOFENCE_TRANSITION_ENTER;
        if (notifyOnExit) transitionTypes |= Geofence.GEOFENCE_TRANSITION_EXIT;
        if (notifyOnDwell) transitionTypes |= Geofence.GEOFENCE_TRANSITION_DWELL;

        Geofence.Builder builder = new Geofence.Builder()
                .setRequestId(identifier)
                .setCircularRegion(lat, lon, (float) radius)
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(transitionTypes);

        if (notifyOnDwell && loiteringDelay > 0) {
            builder.setLoiteringDelay(loiteringDelay);
        }

        return builder.build();
    }

    private void storeGeofence(Map<String, Object> geofenceMap) {
        JSONArray array = readGeofenceStore();
        array.put(new JSONObject(geofenceMap));
        writeGeofenceStore(array);
    }

    private void removeGeofenceFromStore(String identifier) {
        JSONArray array = readGeofenceStore();
        JSONArray updated = new JSONArray();
        for (int i = 0; i < array.length(); i++) {
            JSONObject obj = array.optJSONObject(i);
            if (obj != null && !identifier.equals(obj.optString("identifier"))) {
                updated.put(obj);
            }
        }
        writeGeofenceStore(updated);
    }

    private void enforceMaxMonitoredGeofences() {
        if (maxMonitoredGeofences <= 0) {
            return;
        }
        JSONArray stored = readGeofenceStore();
        int overflow = stored.length() - maxMonitoredGeofences;
        if (overflow <= 0) {
            return;
        }
        trimGeofenceStore(stored, overflow);
    }

    private void trimGeofenceStore(JSONArray stored, int overflow) {
        List<String> removeIds = new ArrayList<>();
        JSONArray remaining = new JSONArray();
        for (int i = 0; i < stored.length(); i++) {
            JSONObject obj = stored.optJSONObject(i);
            if (obj == null) {
                continue;
            }
            if (i < overflow) {
                String id = obj.optString("identifier", null);
                if (id != null) {
                    removeIds.add(id);
                }
            } else {
                remaining.put(obj);
            }
        }
        if (!removeIds.isEmpty()) {
            geofencingClient.removeGeofences(removeIds);
            if (listener != null) listener.onGeofencesChanged(new ArrayList<>(), removeIds);
        }
        writeGeofenceStore(remaining);
    }

    private JSONArray readGeofenceStore() {
        String raw = prefs.getString(KEY_GEOFENCE_STORE, "[]");
        try {
            return new JSONArray(raw);
        } catch (JSONException e) {
            return new JSONArray();
        }
    }

    private void writeGeofenceStore(JSONArray array) {
        prefs.edit().putString(KEY_GEOFENCE_STORE, array.toString()).apply();
    }

    private PendingIntent createGeofencePendingIntent() {
        Intent intent = new Intent(context, GeofenceBroadcastReceiver.class);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 31) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        return PendingIntent.getBroadcast(context, 0, intent, flags);
    }

    // Helpers
    private Map<String, Object> asMap(Object obj) {
        if (obj instanceof Map) {
            return (Map<String, Object>) obj;
        }
        return null;
    }

    private Map<String, Object> toMap(JSONObject json) throws JSONException {
        Map<String, Object> map = new HashMap<>();
        java.util.Iterator<String> keys = json.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            Object value = json.get(key);
            if (value instanceof JSONArray) {
                value = toList((JSONArray) value);
            } else if (value instanceof JSONObject) {
                value = toMap((JSONObject) value);
            }
            map.put(key, value);
        }
        return map;
    }

    private List<Object> toList(JSONArray array) throws JSONException {
        List<Object> list = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            Object value = array.get(i);
            if (value instanceof JSONArray) {
                value = toList((JSONArray) value);
            } else if (value instanceof JSONObject) {
                value = toMap((JSONObject) value);
            }
            list.add(value);
        }
        return list;
    }

    private List<String> extractIdentifiers(JSONArray array) {
        List<String> ids = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            JSONObject obj = array.optJSONObject(i);
            if (obj != null) {
               String id = obj.optString("identifier", null);
               if (id != null) ids.add(id);
            }
        }
        return ids;
    }
}
