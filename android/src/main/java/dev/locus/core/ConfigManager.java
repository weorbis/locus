package dev.locus.core;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import dev.locus.LocusPlugin;

public class ConfigManager {


    private final SharedPreferences prefs;

    public boolean foregroundService = true;
    public String notificationTitle = "Locus";
    public String notificationText = "Tracking location in background.";
    public String notificationIcon = "ic_launcher";
    public int notificationId = 197812504;
    public int notificationImportance = 3;
    public List<String> notificationActions = new ArrayList<>();

    public long activityRecognitionInterval = 10000;
    public long locationUpdateInterval = 10000;
    public long fastestLocationUpdateInterval = 5000;
    public float distanceFilter = 10f;
    public float stationaryRadius = 25f;
    public int minActivityConfidence = 0;
    public int stopTimeoutMinutes = 0;
    public long motionTriggerDelay = 0;
    public long stopDetectionDelay = 0;
    
    public String httpUrl;
    public String httpMethod = "POST";
    public boolean autoSync = false;
    public boolean batchSync = false;
    public int maxBatchSize = 50;
    public int autoSyncThreshold = 0;
    public String persistMode = "none";
    public String httpRootProperty;
    public boolean disableAutoSyncOnCellular = false;
    public int queueMaxDays = 0;
    public int queueMaxRecords = 0;
    public String idempotencyHeader = "Idempotency-Key";
    public Map<String, Object> httpHeaders = new HashMap<>();
    public Map<String, Object> httpParams = new HashMap<>();
    public int httpTimeoutMs = 10000;
    public int maxRetry = 0;
    public int retryDelayMs = 5000;
    public double retryDelayMultiplier = 2.0;
    public int maxRetryDelayMs = 60000;

    public boolean scheduleEnabled = false;
    public List<String> schedule = new ArrayList<>();
    public int heartbeatIntervalSeconds = 0;
    public boolean enableHeadless = false;
    public boolean startOnBoot = false;
    public boolean stopOnTerminate = true;
    public String logLevel = "info";
    public int logMaxDays = 0;
    public int maxDaysToPersist = 0;
    public int maxRecordsToPersist = 0;
    
    public boolean disableMotionActivityUpdates = false;
    public boolean disableStopDetection = false;
    public List<String> triggerActivities = new ArrayList<>();
    public int maxMonitoredGeofences = 0;
    public String desiredAccuracy = "high";

    public ConfigManager(Context context) {
        this.prefs = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);
    }

    public void applyConfig(Map<String, Object> config) {
        if (config == null) {
            return;
        }
        prefs.edit().putString("bg_last_config", new JSONObject(config).toString()).apply();

        Object foreground = config.get("foregroundService");
        if (foreground instanceof Boolean) {
            foregroundService = (Boolean) foreground;
        }
        Object title = config.get("notification") instanceof Map
                ? ((Map<?, ?>) config.get("notification")).get("title")
                : config.get("notificationTitle");
        if (title instanceof String) {
            notificationTitle = (String) title;
        }
        Object text = config.get("notification") instanceof Map
                ? ((Map<?, ?>) config.get("notification")).get("text")
                : config.get("notificationText");
        if (text instanceof String) {
            notificationText = (String) text;
        }
        Object icon = config.get("notification") instanceof Map
                ? ((Map<?, ?>) config.get("notification")).get("smallIcon")
                : config.get("notificationSmallIcon");
        if (icon instanceof String) {
            notificationIcon = (String) icon;
        }
        Object actionsValue = config.get("notification") instanceof Map
                ? ((Map<?, ?>) config.get("notification")).get("actions")
                : null;
        notificationActions.clear();
        if (actionsValue instanceof List) {
            for (Object value : (List<?>) actionsValue) {
                if (value != null) {
                    notificationActions.add(String.valueOf(value));
                }
            }
        }
        
        Object interval = config.get("activityRecognitionInterval");
        if (interval instanceof Number) {
            activityRecognitionInterval = ((Number) interval).longValue();
        }
        Object updateInterval = config.get("locationUpdateInterval");
        if (updateInterval instanceof Number) {
            locationUpdateInterval = ((Number) updateInterval).longValue();
        }
        Object fastestInterval = config.get("fastestLocationUpdateInterval");
        if (fastestInterval instanceof Number) {
            fastestLocationUpdateInterval = ((Number) fastestInterval).longValue();
        }
        Object distance = config.get("distanceFilter");
        if (distance instanceof Number) {
            distanceFilter = ((Number) distance).floatValue();
        }
        Object stationary = config.get("stationaryRadius");
        if (stationary instanceof Number) {
            stationaryRadius = ((Number) stationary).floatValue();
        }
        Object minConfidence = config.get("minimumActivityRecognitionConfidence");
        if (minConfidence instanceof Number) {
            minActivityConfidence = ((Number) minConfidence).intValue();
        }
        Object disableActivityUpdates = config.get("disableMotionActivityUpdates");
        if (disableActivityUpdates instanceof Boolean) {
            disableMotionActivityUpdates = (Boolean) disableActivityUpdates;
        }
        Object disableStop = config.get("disableStopDetection");
        if (disableStop instanceof Boolean) {
            disableStopDetection = (Boolean) disableStop;
        }
        Object triggers = config.get("triggerActivities");
        if (triggers instanceof List) {
            triggerActivities = new ArrayList<>();
            for (Object value : (List<?>) triggers) {
                if (value != null) {
                    triggerActivities.add(String.valueOf(value));
                }
            }
        }
        
        Object autoSyncValue = config.get("autoSync");
        if (autoSyncValue instanceof Boolean) {
            autoSync = (Boolean) autoSyncValue;
        }
        Object batchSyncValue = config.get("batchSync");
        if (batchSyncValue instanceof Boolean) {
            batchSync = (Boolean) batchSyncValue;
        }
        Object maxBatch = config.get("maxBatchSize");
        if (maxBatch instanceof Number) {
            maxBatchSize = ((Number) maxBatch).intValue();
        }
        Object threshold = config.get("autoSyncThreshold");
        if (threshold instanceof Number) {
            autoSyncThreshold = ((Number) threshold).intValue();
        }
        Object disableAutoSyncValue = config.get("disableAutoSyncOnCellular");
        if (disableAutoSyncValue instanceof Boolean) {
            disableAutoSyncOnCellular = (Boolean) disableAutoSyncValue;
        }
        Object queueDays = config.get("queueMaxDays");
        if (queueDays instanceof Number) {
            queueMaxDays = ((Number) queueDays).intValue();
        }
        Object queueRecords = config.get("queueMaxRecords");
        if (queueRecords instanceof Number) {
            queueMaxRecords = ((Number) queueRecords).intValue();
        }
        Object idempotency = config.get("idempotencyHeader");
        if (idempotency instanceof String) {
            idempotencyHeader = (String) idempotency;
        }
        Object persistValue = config.get("persistMode");
        if (persistValue instanceof String) {
            persistMode = (String) persistValue;
        }
        Object maxDays = config.get("maxDaysToPersist");
        if (maxDays instanceof Number) {
            maxDaysToPersist = ((Number) maxDays).intValue();
        }
        Object maxRecords = config.get("maxRecordsToPersist");
        if (maxRecords instanceof Number) {
            maxRecordsToPersist = ((Number) maxRecords).intValue();
        }
        Object maxGeofences = config.get("maxMonitoredGeofences");
        if (maxGeofences instanceof Number) {
            maxMonitoredGeofences = ((Number) maxGeofences).intValue();
        }
        Object rootProperty = config.get("httpRootProperty");
        if (rootProperty instanceof String) {
            httpRootProperty = (String) rootProperty;
        }
        Object urlValue = config.get("url");
        if (urlValue instanceof String) {
            httpUrl = (String) urlValue;
        }
        Object timeoutValue = config.get("httpTimeout");
        if (timeoutValue instanceof Number) {
            httpTimeoutMs = ((Number) timeoutValue).intValue();
        }
        Object maxRetryValue = config.get("maxRetry");
        if (maxRetryValue instanceof Number) {
            maxRetry = ((Number) maxRetryValue).intValue();
        }
        Object retryDelayValue = config.get("retryDelay");
        if (retryDelayValue instanceof Number) {
            retryDelayMs = ((Number) retryDelayValue).intValue();
        }
        Object retryMultiplier = config.get("retryDelayMultiplier");
        if (retryMultiplier instanceof Number) {
            retryDelayMultiplier = ((Number) retryMultiplier).doubleValue();
        }
        Object maxRetryDelayValue = config.get("maxRetryDelay");
        if (maxRetryDelayValue instanceof Number) {
            maxRetryDelayMs = ((Number) maxRetryDelayValue).intValue();
        }
        Object methodValue = config.get("method");
        if (methodValue instanceof String) {
            httpMethod = (String) methodValue;
        }
        Object headersValue = config.get("headers");
        if (headersValue instanceof Map) {
            httpHeaders = asMap(headersValue);
        }
        Object paramsValue = config.get("params");
        if (paramsValue instanceof Map) {
            httpParams = asMap(paramsValue);
        }
        
        Object scheduleValue = config.get("schedule");
        if (scheduleValue instanceof List) {
            schedule = new ArrayList<>();
            for (Object value : (List<?>) scheduleValue) {
                if (value != null) {
                    schedule.add(String.valueOf(value));
                }
            }
        }
        
        Object logLevelValue = config.get("logLevel");
        if (logLevelValue instanceof String) {
            logLevel = (String) logLevelValue;
        }
        Object logDays = config.get("logMaxDays");
        if (logDays instanceof Number) {
            logMaxDays = ((Number) logDays).intValue();
        }
        Object headless = config.get("enableHeadless");
        if (headless instanceof Boolean) {
            enableHeadless = (Boolean) headless;
        }
        Object startBoot = config.get("startOnBoot");
        if (startBoot instanceof Boolean) {
            startOnBoot = (Boolean) startBoot;
        }
        Object stopTerm = config.get("stopOnTerminate");
        if (stopTerm instanceof Boolean) {
            stopOnTerminate = (Boolean) stopTerm;
        }
        Object heartbeat = config.get("heartbeatInterval");
        if (heartbeat instanceof Number) {
            heartbeatIntervalSeconds = ((Number) heartbeat).intValue();
        }
        Object stopTimeout = config.get("stopTimeout");
        if (stopTimeout instanceof Number) {
            stopTimeoutMinutes = ((Number) stopTimeout).intValue();
        }
        Object triggerDelay = config.get("motionTriggerDelay");
        if (triggerDelay instanceof Number) {
            motionTriggerDelay = ((Number) triggerDelay).longValue();
        }
        Object stopDelay = config.get("stopDetectionDelay");
        if (stopDelay instanceof Number) {
            stopDetectionDelay = ((Number) stopDelay).longValue();
        }
        
        Object desiredAccuracyValue = config.get("desiredAccuracy");
        if (desiredAccuracyValue instanceof String) {
            desiredAccuracy = (String) desiredAccuracyValue;
        }

        prefs.edit()
                .putBoolean("bg_enable_headless", enableHeadless)
                .putBoolean("bg_start_on_boot", startOnBoot)
                .putBoolean("bg_stop_on_terminate", stopOnTerminate)
                .apply();
    }
    
    public Map<String, Object> buildConfigSnapshot() {
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
            if (value instanceof org.json.JSONArray) {
                // simple list support if needed, or stringify
                value = value.toString();
            } else if (value instanceof JSONObject) {
                value = toMap((JSONObject) value);
            }
            map.put(key, value);
        }
        return map;
    }
}
