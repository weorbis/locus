package dev.locus.core;

import android.annotation.SuppressLint;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.location.Location;
import android.location.LocationManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.core.content.ContextCompat;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.locus.activity.MotionManager;
import dev.locus.geofence.GeofenceManager;
import dev.locus.location.LocationClient;

public class LocationTracker {
    public interface AutoSyncChecker {
        boolean isAutoSyncAllowed();
    }

    private static final String TAG = "locus";

    private final Context context;
    private final ConfigManager config;
    private final LocationClient locationClient;
    private final MotionManager motionManager;
    private final GeofenceManager geofenceManager;
    private final SyncManager syncManager;
    private final StateManager stateManager;
    private final ForegroundServiceController foregroundServiceController;
    private final EventDispatcher eventDispatcher;
    private final LogManager logManager;
    private final AutoSyncChecker autoSyncChecker;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private Location lastLocation;
    private boolean enabled = false;
    private Runnable heartbeatRunnable;
    private BroadcastReceiver providerReceiver;

    public LocationTracker(Context context,
                           ConfigManager config,
                           LocationClient locationClient,
                           MotionManager motionManager,
                           GeofenceManager geofenceManager,
                           SyncManager syncManager,
                           StateManager stateManager,
                           ForegroundServiceController foregroundServiceController,
                           EventDispatcher eventDispatcher,
                           LogManager logManager,
                           AutoSyncChecker autoSyncChecker) {
        this.context = context;
        this.config = config;
        this.locationClient = locationClient;
        this.motionManager = motionManager;
        this.geofenceManager = geofenceManager;
        this.syncManager = syncManager;
        this.stateManager = stateManager;
        this.foregroundServiceController = foregroundServiceController;
        this.eventDispatcher = eventDispatcher;
        this.logManager = logManager;
        this.autoSyncChecker = autoSyncChecker;

        this.locationClient.setListener(new LocationClient.LocationClientListener() {
            @Override
            public void onLocation(Location location) {
                if (location == null) return;
                lastLocation = location;
                stateManager.updateOdometer(location);
                emitLocationEvent(location, "location");
            }

            @Override
            public void onLocationError(String code, String message) {
                logManager.log("error", "Location error: " + message);
            }
        });

        this.motionManager.setListener(new MotionManager.MotionListener() {
            @Override
            public void onMotionChange(boolean isMoving) {
                locationClient.updateRequest(isMoving);
                if (lastLocation != null) {
                    emitLocationEvent(lastLocation, "motionchange");
                }
            }

            @Override
            public void onActivityChange(String type, int confidence) {
                if (lastLocation != null) {
                    emitLocationEvent(lastLocation, "activitychange");
                }
            }
        });
    }

    public boolean isEnabled() {
        return enabled;
    }

    public boolean isMoving() {
        return motionManager.isMoving();
    }

    public Location getLastLocation() {
        return lastLocation;
    }

    public Map<String, Object> buildState() {
        Map<String, Object> state = new HashMap<>();
        state.put("enabled", enabled);
        state.put("isMoving", motionManager.isMoving());
        state.put("odometer", stateManager.getOdometerValue());
        if (lastLocation != null) {
            state.put("location", buildLocationPayload(lastLocation, "location"));
        }
        return state;
    }

    public void applyConfig(Map<String, Object> configMap) {
        if (configMap == null) {
            return;
        }
        
        int previousHeartbeatInterval = config.heartbeatIntervalSeconds;
        
        config.applyConfig(configMap);

        if (configMap.containsKey("maxMonitoredGeofences")) {
            geofenceManager.setMaxMonitoredGeofences(config.maxMonitoredGeofences);
        }

        if (enabled) {
            if (config.disableMotionActivityUpdates) {
                motionManager.stop();
            } else {
                motionManager.start();
            }
            locationClient.updateRequest(motionManager.isMoving());
            
            if (configMap.containsKey("heartbeatInterval") && 
                previousHeartbeatInterval != config.heartbeatIntervalSeconds) {
                restartHeartbeat();
            }
        }
    }

    @SuppressLint("MissingPermission")
    public void startTracking() {
        if (enabled) {
            return;
        }
        if (!locationClient.hasPermission()) {
            Log.w(TAG, "Location permission missing; tracking not started.");
            return;
        }
        enabled = true;

        if (config.foregroundService && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            foregroundServiceController.start(config);
        }

        motionManager.start();
        locationClient.start();
        geofenceManager.startGeofencesInternal();
        registerProviderReceiver();
        emitProviderChange();
        emitEnabledChange(true);
        startHeartbeat();
        logManager.log("info", "start");
    }

    public void stopTracking() {
        if (!enabled) {
            return;
        }
        enabled = false;
        motionManager.stop();
        locationClient.stop();
        foregroundServiceController.stop();
        unregisterProviderReceiver();
        emitEnabledChange(false);
        stopHeartbeat();
        logManager.log("info", "stop");
    }

    public void changePace(boolean moving) {
        motionManager.setPace(moving);
    }

    public void emitScheduleEvent() {
        if (!config.scheduleEnabled || lastLocation == null) {
            return;
        }
        emitLocationEvent(lastLocation, "configManager.schedule");
    }

    public void syncNow() {
        Map<String, Object> payload = null;
        if (lastLocation != null) {
            payload = buildLocationPayload(lastLocation, "location");
        }
        syncManager.syncNow(payload);
    }

    public void startHeartbeat() {
        if (config.heartbeatIntervalSeconds <= 0 || heartbeatRunnable != null) {
            return;
        }
        heartbeatRunnable = new Runnable() {
            @Override
            public void run() {
                if (enabled && lastLocation != null) {
                    emitLocationEvent(lastLocation, "heartbeat");
                }
                mainHandler.postDelayed(this, config.heartbeatIntervalSeconds * 1000L);
            }
        };
        mainHandler.postDelayed(heartbeatRunnable, config.heartbeatIntervalSeconds * 1000L);
    }

    public void stopHeartbeat() {
        if (heartbeatRunnable != null) {
            mainHandler.removeCallbacks(heartbeatRunnable);
            heartbeatRunnable = null;
        }
    }

    /**
     * Restarts the heartbeat with the current configuration.
     * Call when heartbeat interval changes dynamically.
     */
    public void restartHeartbeat() {
        stopHeartbeat();
        startHeartbeat();
    }

    public Map<String, Object> buildLocationPayload(Location location, String eventName) {
        Map<String, Object> coords = new HashMap<>();
        coords.put("latitude", location.getLatitude());
        coords.put("longitude", location.getLongitude());
        coords.put("accuracy", location.getAccuracy());
        coords.put("speed", location.getSpeed());
        coords.put("heading", location.getBearing());
        coords.put("altitude", location.getAltitude());

        Map<String, Object> activity = new HashMap<>();
        activity.put("type", motionManager.getLastActivityType());
        activity.put("confidence", motionManager.getLastActivityConfidence());

        Map<String, Object> payload = new HashMap<>();
        payload.put("uuid", UUID.randomUUID().toString());
        payload.put("timestamp", Instant.ofEpochMilli(location.getTime()).toString());
        payload.put("coords", coords);
        payload.put("activity", activity);
        payload.put("event", eventName);
        payload.put("is_moving", motionManager.isMoving());
        payload.put("odometer", stateManager.getOdometerValue());
        return payload;
    }

    private void emitLocationEvent(Location location, String eventName) {
        Map<String, Object> payload = buildLocationPayload(location, eventName);
        Map<String, Object> event = new HashMap<>();
        event.put("type", eventName);
        event.put("data", payload);
        eventDispatcher.sendEvent(event);
        if (PersistencePolicy.shouldPersist(config, eventName)) {
            stateManager.storeLocationPayload(payload, config.maxDaysToPersist, config.maxRecordsToPersist);
        }
        if (config.autoSync && config.httpUrl != null && !config.httpUrl.isEmpty() && autoSyncChecker.isAutoSyncAllowed()) {
            if (config.batchSync) {
                syncManager.attemptBatchSync();
            } else {
                syncManager.syncNow(payload);
            }
        }
    }

    private void emitProviderChange() {
        Map<String, Object> payload = new HashMap<>();
        boolean locationEnabled = isLocationEnabled();
        payload.put("enabled", locationEnabled);
        payload.put("status", locationEnabled ? "enabled" : "disabled");
        payload.put("availability", locationEnabled ? "available" : "unavailable");
        payload.put("authorizationStatus", resolveAuthorizationStatus());
        payload.put("accuracyAuthorization", resolveAccuracyAuthorization());

        Map<String, Object> event = new HashMap<>();
        event.put("type", "providerchange");
        event.put("data", payload);
        eventDispatcher.sendEvent(event);
    }

    private void emitEnabledChange(boolean nextEnabled) {
        Map<String, Object> event = new HashMap<>();
        event.put("type", "enabledchange");
        event.put("data", nextEnabled);
        eventDispatcher.sendEvent(event);
    }

    private boolean isLocationEnabled() {
        LocationManager locationManager = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
        if (locationManager == null) {
            return false;
        }
        return locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
                || locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
    }

    private String resolveAuthorizationStatus() {
        if (!hasLocationPermission()) {
            return "denied";
        }
        boolean fine = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
        if (fine) {
            return "always";
        }
        return "whenInUse";
    }

    private String resolveAccuracyAuthorization() {
        boolean fine = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
        return fine ? "full" : "reduced";
    }

    private boolean hasLocationPermission() {
        boolean fine = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
        boolean coarse = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_COARSE_LOCATION)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
        return fine || coarse;
    }

    private void registerProviderReceiver() {
        if (providerReceiver != null) {
            return;
        }
        providerReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                emitProviderChange();
            }
        };
        IntentFilter filter = new IntentFilter(LocationManager.PROVIDERS_CHANGED_ACTION);
        filter.addAction(LocationManager.MODE_CHANGED_ACTION);
        context.registerReceiver(providerReceiver, filter);
    }

    private void unregisterProviderReceiver() {
        if (providerReceiver == null) {
            return;
        }
        try {
            context.unregisterReceiver(providerReceiver);
        } catch (IllegalArgumentException e) {
            // Receiver was already unregistered
            Log.w(TAG, "Provider receiver already unregistered");
        }
        providerReceiver = null;
    }

    /**
     * Releases all resources. Call when plugin is detached.
     */
    public void release() {
        stopTracking();
        locationClient.stop();
        motionManager.stop();
    }
}
