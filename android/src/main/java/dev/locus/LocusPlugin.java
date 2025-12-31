package dev.locus;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.SharedPreferences;
import android.location.Location;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.locus.activity.MotionManager;
import dev.locus.core.BackgroundTaskManager;
import dev.locus.core.ConfigManager;
import dev.locus.core.EventDispatcher;
import dev.locus.core.ForegroundServiceController;
import dev.locus.core.HeadlessDispatcher;
import dev.locus.core.LocationTracker;
import dev.locus.core.LogManager;
import dev.locus.core.PreferenceEventHandler;
import dev.locus.core.Scheduler;
import dev.locus.core.StateManager;
import dev.locus.core.SyncManager;
import dev.locus.core.SystemMonitor;
import dev.locus.geofence.GeofenceManager;
import dev.locus.location.LocationClient;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

@SuppressLint("LongLogTag")
public class LocusPlugin implements FlutterPlugin,
        MethodChannel.MethodCallHandler,
        EventChannel.StreamHandler,
        ActivityAware,
        SharedPreferences.OnSharedPreferenceChangeListener {

    private static final String TAG = "locus";
    private static final String METHOD_CHANNEL = "locus/methods";
    private static final String EVENT_CHANNEL = "locus/events";
    public static final String PREFS_NAME = "dev.locus.preferences";
    public static final String KEY_ACTIVITY_EVENT = "bg_activity_event";
    public static final String KEY_GEOFENCE_EVENT = "bg_geofence_event";
    public static final String KEY_NOTIFICATION_ACTION = "bg_notification_action";

    private MethodChannel methodChannel;
    private EventChannel eventChannel;
    private Context androidContext;
    private SharedPreferences prefs;
    private boolean isListenerRegistered = false;

    private ConfigManager configManager;
    private StateManager stateManager;
    private LogManager logManager;
    private HeadlessDispatcher headlessDispatcher;
    private EventDispatcher eventDispatcher;
    private SystemMonitor systemMonitor;
    private BackgroundTaskManager backgroundTaskManager;
    private ForegroundServiceController foregroundServiceController;
    private GeofenceManager geofenceManager;
    private LocationClient locationClient;
    private MotionManager motionManager;
    private SyncManager syncManager;
    private LocationTracker locationTracker;
    private Scheduler scheduler;
    private PreferenceEventHandler preferenceEventHandler;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        androidContext = binding.getApplicationContext();
        prefs = androidContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        methodChannel = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANNEL);
        methodChannel.setMethodCallHandler(this);
        eventChannel = new EventChannel(binding.getBinaryMessenger(), EVENT_CHANNEL);
        eventChannel.setStreamHandler(this);

        configManager = new ConfigManager(androidContext);
        stateManager = new StateManager(androidContext);
        logManager = new LogManager(configManager, stateManager.getLogStore());
        headlessDispatcher = new HeadlessDispatcher(androidContext, configManager, prefs);
        eventDispatcher = new EventDispatcher(headlessDispatcher);
        systemMonitor = new SystemMonitor(androidContext, new SystemMonitor.Listener() {
            @Override
            public void onConnectivityChange(Map<String, Object> payload) {
                emitConnectivityChange(payload);
            }

            @Override
            public void onPowerSaveChange(boolean enabled) {
                emitPowerSaveChange(enabled);
            }
        });

        backgroundTaskManager = new BackgroundTaskManager(androidContext);
        foregroundServiceController = new ForegroundServiceController(androidContext);

        geofenceManager = new GeofenceManager(androidContext, this::emitGeofencesChange);
        locationClient = new LocationClient(androidContext, configManager);
        motionManager = new MotionManager(androidContext, configManager);

        syncManager = new SyncManager(androidContext, configManager,
                stateManager.getLocationStore(), stateManager.getQueueStore(),
                new SyncManager.SyncListener() {
                    @Override
                    public void onHttpEvent(Map<String, Object> eventData) {
                        eventDispatcher.sendEvent(eventData);
                    }

                    @Override
                    public void onLog(String level, String message) {
                        logManager.log(level, message);
                    }
                });

        locationTracker = new LocationTracker(androidContext, configManager, locationClient, motionManager,
                geofenceManager, syncManager, stateManager, foregroundServiceController, eventDispatcher,
                logManager, () -> systemMonitor.isAutoSyncAllowed(configManager));

        preferenceEventHandler = new PreferenceEventHandler(configManager, motionManager, geofenceManager,
                stateManager, syncManager, eventDispatcher,
                () -> systemMonitor.isAutoSyncAllowed(configManager));

        scheduler = new Scheduler(configManager, shouldBeEnabled -> {
            if (shouldBeEnabled && !locationTracker.isEnabled()) {
                locationTracker.startTracking();
                locationTracker.emitScheduleEvent();
                return true;
            } else if (!shouldBeEnabled && locationTracker.isEnabled()) {
                locationTracker.stopTracking();
                return false;
            }
            return shouldBeEnabled;
        });

        applyStoredConfig();
        systemMonitor.registerConnectivity();
        systemMonitor.registerPowerSave();
        if (prefs != null && !isListenerRegistered) {
            prefs.registerOnSharedPreferenceChangeListener(this);
            isListenerRegistered = true;
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (configManager.stopOnTerminate) {
            locationTracker.stopTracking();
        }
        locationTracker.release();
        systemMonitor.unregisterConnectivity();
        systemMonitor.unregisterPowerSave();
        scheduler.stop();
        backgroundTaskManager.release();
        syncManager.release();
        if (prefs != null && isListenerRegistered) {
            prefs.unregisterOnSharedPreferenceChangeListener(this);
            isListenerRegistered = false;
        }
        eventDispatcher.setEventSink(null);
        eventChannel.setStreamHandler(null);
        methodChannel.setMethodCallHandler(null);
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        eventDispatcher.setEventSink(events);
        emitConnectivityChange(systemMonitor.readConnectivityEvent());
        emitPowerSaveChange(systemMonitor.readPowerSaveState());
    }

    @Override
    public void onCancel(Object arguments) {
        eventDispatcher.setEventSink(null);
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        if (prefs != null && isListenerRegistered) {
            prefs.unregisterOnSharedPreferenceChangeListener(this);
            isListenerRegistered = false;
        }
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        if (prefs != null && !isListenerRegistered) {
            prefs.registerOnSharedPreferenceChangeListener(this);
            isListenerRegistered = true;
        }
    }

    @Override
    public void onDetachedFromActivity() {
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "ready":
                locationTracker.applyConfig(asMap(call.arguments));
                result.success(locationTracker.buildState());
                break;
            case "start":
                locationTracker.startTracking();
                result.success(locationTracker.buildState());
                break;
            case "stop":
                locationTracker.stopTracking();
                result.success(locationTracker.buildState());
                break;
            case "getState":
                result.success(locationTracker.buildState());
                break;
            case "getCurrentPosition":
                getCurrentPosition(result);
                break;
            case "setConfig":
                locationTracker.applyConfig(asMap(call.arguments));
                result.success(true);
                break;
            case "reset":
                locationTracker.applyConfig(asMap(call.arguments));
                result.success(true);
                break;
            case "setOdometer":
                if (call.arguments instanceof Number) {
                    double val = ((Number) call.arguments).doubleValue();
                    stateManager.setOdometer(val);
                    result.success(val);
                } else {
                    result.error("INVALID_ARGUMENT", "Expected numeric odometer value", null);
                }
                break;
            case "changePace":
                Boolean moving = call.arguments instanceof Boolean ? (Boolean) call.arguments : null;
                if (moving != null) {
                    locationTracker.changePace(moving);
                }
                result.success(true);
                break;
            case "addGeofence":
                geofenceManager.addGeofence(asMap(call.arguments), result);
                break;
            case "addGeofences":
                geofenceManager.addGeofences(asList(call.arguments), result);
                break;
            case "removeGeofence":
                geofenceManager.removeGeofence(call.arguments, result);
                break;
            case "removeGeofences":
                geofenceManager.removeGeofences(result);
                break;
            case "getGeofence":
                geofenceManager.getGeofence(call.arguments, result);
                break;
            case "getGeofences":
                geofenceManager.getGeofences(result);
                break;
            case "geofenceExists":
                geofenceManager.geofenceExists(call.arguments, result);
                break;
            case "destroyLocations":
                stateManager.clearLocations();
                result.success(true);
                break;
            case "getLocations":
                int limit = 0;
                Map<String, Object> args = asMap(call.arguments);
                if (args != null && args.get("limit") instanceof Number) {
                    limit = ((Number) args.get("limit")).intValue();
                }
                result.success(stateManager.getStoredLocations(limit));
                break;
            case "enqueue":
                Map<String, Object> enqueueArgs = asMap(call.arguments);
                if (enqueueArgs == null) {
                    result.error("INVALID_ARGUMENT", "Expected payload map", null);
                    break;
                }
                Object payloadObj = enqueueArgs.get("payload");
                if (!(payloadObj instanceof Map)) {
                    result.error("INVALID_ARGUMENT", "Missing payload map", null);
                    break;
                }
                String type = enqueueArgs.get("type") instanceof String ? (String) enqueueArgs.get("type") : null;
                String idempotencyKey = enqueueArgs.get("idempotencyKey") instanceof String
                        ? (String) enqueueArgs.get("idempotencyKey")
                        : UUID.randomUUID().toString();
                String id = stateManager.enqueue(asMap(payloadObj), type, idempotencyKey,
                        configManager.queueMaxDays, configManager.queueMaxRecords);
                result.success(id);
                break;
            case "getQueue":
                int queueLimit = 0;
                Map<String, Object> queueArgs = asMap(call.arguments);
                if (queueArgs != null && queueArgs.get("limit") instanceof Number) {
                    queueLimit = ((Number) queueArgs.get("limit")).intValue();
                }
                result.success(stateManager.getQueue(queueLimit));
                break;
            case "clearQueue":
                stateManager.clearQueue();
                result.success(true);
                break;
            case "syncQueue":
                int syncLimit = 0;
                Map<String, Object> syncArgs = asMap(call.arguments);
                if (syncArgs != null && syncArgs.get("limit") instanceof Number) {
                    syncLimit = ((Number) syncArgs.get("limit")).intValue();
                }
                result.success(syncManager.syncQueue(syncLimit));
                break;
            case "storeTripState":
                Map<String, Object> tripState = asMap(call.arguments);
                if (tripState == null) {
                    result.error("INVALID_ARGUMENT", "Expected trip state map", null);
                    break;
                }
                stateManager.storeTripState(tripState);
                result.success(true);
                break;
            case "readTripState":
                result.success(stateManager.readTripState());
                break;
            case "clearTripState":
                stateManager.clearTripState();
                result.success(true);
                break;
            case "getConfig":
                result.success(buildConfigSnapshot());
                break;
            case "getDiagnosticsMetadata":
                result.success(buildDiagnosticsMetadata());
                break;
            case "registerHeadlessTask":
                if (call.arguments instanceof Map) {
                    Map<String, Object> map = asMap(call.arguments);
                    Object dispatcher = map != null ? map.get("dispatcher") : null;
                    Object callback = map != null ? map.get("callback") : null;
                    if (dispatcher instanceof Number && callback instanceof Number) {
                        prefs.edit()
                                .putLong("bg_headless_dispatcher", ((Number) dispatcher).longValue())
                                .putLong("bg_headless_callback", ((Number) callback).longValue())
                                .apply();
                        result.success(true);
                    } else {
                        result.success(false);
                    }
                } else if (call.arguments instanceof Number) {
                    prefs.edit().putLong("bg_headless_callback", ((Number) call.arguments).longValue()).apply();
                    result.success(true);
                } else {
                    result.success(false);
                }
                break;
            case "startGeofences":
                geofenceManager.startGeofences(result);
                break;
            case "startSchedule":
                configManager.scheduleEnabled = true;
                locationTracker.emitScheduleEvent();
                scheduler.start();
                scheduler.applyScheduleState();
                result.success(true);
                break;
            case "stopSchedule":
                configManager.scheduleEnabled = false;
                scheduler.stop();
                result.success(true);
                break;
            case "sync":
                locationTracker.syncNow();
                result.success(true);
                break;
            case "startBackgroundTask":
                result.success(backgroundTaskManager.start());
                break;
            case "stopBackgroundTask":
                if (call.arguments instanceof Number) {
                    backgroundTaskManager.stop(((Number) call.arguments).intValue());
                }
                result.success(true);
                break;
            case "getLog":
                result.success(stateManager.readLog());
                break;
            case "emailLog":
            case "playSound":
                result.success(true);
                break;
            case "getBatteryStats":
                result.success(buildBatteryStats());
                break;
            case "getPowerState":
                result.success(buildPowerState());
                break;
            case "getNetworkType":
                result.success(getNetworkType());
                break;
            case "setSpoofDetection":
                // Spoof detection is handled on Dart side, just acknowledge
                result.success(true);
                break;
            case "startSignificantChangeMonitoring":
                // Significant change monitoring is handled on Dart side
                result.success(true);
                break;
            case "stopSignificantChangeMonitoring":
                // Significant change monitoring is handled on Dart side
                result.success(true);
                break;
            default:
                result.notImplemented();
        }
    }

    @Override
    public void onSharedPreferenceChanged(SharedPreferences sharedPreferences, String key) {
        preferenceEventHandler.handlePreferenceChange(sharedPreferences, key);
    }

    private void getCurrentPosition(MethodChannel.Result result) {
        if (!locationClient.hasPermission()) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null);
            return;
        }
        locationClient.getCurrentPosition(new LocationClient.LocationResultCallback() {
            @Override
            public void onSuccess(Location location) {
                Map<String, Object> payload = locationTracker.buildLocationPayload(location, "location");
                result.success(payload);
            }

            @Override
            public void onError(String code, String message) {
                result.error(code, message, null);
            }
        });
    }

    private void emitConnectivityChange(Map<String, Object> payload) {
        Map<String, Object> event = new HashMap<>();
        event.put("type", "connectivitychange");
        event.put("data", payload);
        eventDispatcher.sendEvent(event);
    }

    private void emitPowerSaveChange(boolean enabled) {
        Map<String, Object> event = new HashMap<>();
        event.put("type", "powersavechange");
        event.put("data", enabled);
        eventDispatcher.sendEvent(event);
    }

    private void emitGeofencesChange(List<String> added, List<String> removed) {
        Map<String, Object> payload = new HashMap<>();
        payload.put("on", added);
        payload.put("off", removed);
        Map<String, Object> event = new HashMap<>();
        event.put("type", "geofenceschange");
        event.put("data", payload);
        eventDispatcher.sendEvent(event);
    }

    private void applyStoredConfig() {
        String configJson = prefs.getString("bg_last_config", null);
        if (configJson == null) {
            return;
        }
        try {
            JSONObject json = new JSONObject(configJson);
            locationTracker.applyConfig(toMap(json));
        } catch (JSONException e) {
            Log.w(TAG, "Failed to restore config: " + e.getMessage());
        }
    }

    private Map<String, Object> buildConfigSnapshot() {
        String configJson = prefs.getString("bg_last_config", null);
        if (configJson == null) {
            return new HashMap<>();
        }
        try {
            return toMap(new JSONObject(configJson));
        } catch (JSONException e) {
            return new HashMap<>();
        }
    }

    private Map<String, Object> buildDiagnosticsMetadata() {
        Map<String, Object> metadata = new HashMap<>();
        metadata.put("platform", "android");
        metadata.put("sdkInt", Build.VERSION.SDK_INT);
        metadata.put("manufacturer", Build.MANUFACTURER);
        metadata.put("model", Build.MODEL);
        metadata.put("powerSaveMode", systemMonitor.readPowerSaveState());
        metadata.put("hasLocationPermission", hasLocationPermission());
        metadata.put("hasActivityPermission", hasActivityPermission());
        metadata.put("hasBackgroundLocationPermission", hasBackgroundLocationPermission());
        return metadata;
    }

    private boolean hasLocationPermission() {
        boolean fine = ContextCompat.checkSelfPermission(androidContext, android.Manifest.permission.ACCESS_FINE_LOCATION)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
        boolean coarse = ContextCompat.checkSelfPermission(androidContext, android.Manifest.permission.ACCESS_COARSE_LOCATION)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
        return fine || coarse;
    }

    private boolean hasActivityPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return true;
        }
        return ContextCompat.checkSelfPermission(androidContext, android.Manifest.permission.ACTIVITY_RECOGNITION)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
    }

    private boolean hasBackgroundLocationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return true;
        }
        return ContextCompat.checkSelfPermission(androidContext, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
    }

    private Map<String, Object> buildBatteryStats() {
        Map<String, Object> stats = new HashMap<>();
        android.content.Intent batteryStatus = androidContext.registerReceiver(null,
                new android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED));
        if (batteryStatus != null) {
            int level = batteryStatus.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1);
            int scale = batteryStatus.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1);
            double batteryLevel = level >= 0 && scale > 0 ? (level / (double) scale) * 100.0 : -1;
            stats.put("batteryLevel", (int) batteryLevel);
            stats.put("isCharging", batteryStatus.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1)
                    == android.os.BatteryManager.BATTERY_STATUS_CHARGING);
        }
        stats.put("estimatedDrainPerHour", 0.0); // Would require tracking over time
        stats.put("locationCount", 0);
        return stats;
    }

    private Map<String, Object> buildPowerState() {
        Map<String, Object> state = new HashMap<>();
        android.content.Intent batteryStatus = androidContext.registerReceiver(null,
                new android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED));
        if (batteryStatus != null) {
            int level = batteryStatus.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1);
            int scale = batteryStatus.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1);
            double batteryLevel = level >= 0 && scale > 0 ? (level / (double) scale) * 100.0 : -1;
            state.put("batteryLevel", (int) batteryLevel);
            int status = batteryStatus.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1);
            state.put("isCharging", status == android.os.BatteryManager.BATTERY_STATUS_CHARGING
                    || status == android.os.BatteryManager.BATTERY_STATUS_FULL);
        } else {
            state.put("batteryLevel", 50);
            state.put("isCharging", false);
        }
        state.put("isPowerSaveMode", systemMonitor.readPowerSaveState());
        return state;
    }

    private String getNetworkType() {
        android.net.ConnectivityManager cm = (android.net.ConnectivityManager)
                androidContext.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (cm == null) {
            return "none";
        }
        android.net.NetworkCapabilities caps = cm.getNetworkCapabilities(cm.getActiveNetwork());
        if (caps == null) {
            return "none";
        }
        if (caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)) {
            return "wifi";
        }
        if (caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR)) {
            return "cellular";
        }
        if (caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET)) {
            return "wifi";
        }
        return "unknown";
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> asMap(Object arguments) {
        if (arguments instanceof Map) {
            return (Map<String, Object>) arguments;
        }
        return null;
    }

    @SuppressWarnings("unchecked")
    private List<Object> asList(Object arguments) {
        if (arguments instanceof List) {
            return (List<Object>) arguments;
        }
        return new ArrayList<>();
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
