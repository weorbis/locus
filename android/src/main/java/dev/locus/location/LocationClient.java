package dev.locus.location;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.Location;
import android.os.Build;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;

import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.Priority;
import com.google.android.gms.tasks.CancellationTokenSource;

import dev.locus.core.ConfigManager;

public class LocationClient {

    private static final String TAG = "locus.LocationClient";
    private final Context context;
    private final ConfigManager config;
    private final FusedLocationProviderClient fusedLocationClient;
    
    private LocationCallback locationCallback;
    private LocationRequest locationRequest;
    private LocationClientListener listener;
    
    // State
    private int currentPriority = Priority.PRIORITY_HIGH_ACCURACY;

    public interface LocationClientListener {
        void onLocation(Location location);
        void onLocationError(String code, String message);
    }
    
    public interface LocationResultCallback {
        void onSuccess(Location location);
        void onError(String code, String message);
    }

    public LocationClient(Context context, ConfigManager config) {
        this.context = context;
        this.config = config;
        this.fusedLocationClient = LocationServices.getFusedLocationProviderClient(context);
    }
    
    public void setListener(LocationClientListener listener) {
        this.listener = listener;
    }

    @SuppressLint("MissingPermission")
    public void start() {
        if (!hasPermission()) {
            if (listener != null) listener.onLocationError("PERMISSION_DENIED", "Location permission missing");
            return;
        }
        
        stop(); 
        
        locationRequest = buildLocationRequest(config.desiredAccuracy, config.stationaryRadius); // Default to stationary
        locationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(@NonNull LocationResult locationResult) {
                Location location = locationResult.getLastLocation();
                if (location != null && listener != null) {
                    listener.onLocation(location);
                }
            }
        };
        
        fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, Looper.getMainLooper());
        Log.i(TAG, "Location updates started");
    }

    public void stop() {
        if (locationCallback != null) {
            fusedLocationClient.removeLocationUpdates(locationCallback);
            locationCallback = null;
            Log.i(TAG, "Location updates stopped");
        }
    }

    @SuppressLint("MissingPermission")
    public void updateRequest(boolean isMoving) {
        if (locationCallback == null) {
            return;
        }
        float minDistance = isMoving ? config.distanceFilter : config.stationaryRadius;
        
        LocationRequest newRequest = buildLocationRequest(config.desiredAccuracy, minDistance);
        
        fusedLocationClient.removeLocationUpdates(locationCallback);
        fusedLocationClient.requestLocationUpdates(newRequest, locationCallback, Looper.getMainLooper());
        
        Log.i(TAG, "Location request updated. Moving: " + isMoving + ", Distance: " + minDistance);
    }

    @SuppressLint("MissingPermission")
    public void getCurrentPosition(LocationResultCallback callback) {
        if (!hasPermission()) {
            callback.onError("PERMISSION_DENIED", "Location permission not granted");
            return;
        }
        
        CancellationTokenSource cancellationToken = new CancellationTokenSource();
        fusedLocationClient.getCurrentLocation(currentPriority, cancellationToken.getToken())
                .addOnSuccessListener(location -> {
                    if (location == null) {
                        callback.onError("LOCATION_ERROR", "No location available");
                    } else {
                        callback.onSuccess(location);
                    }
                })
                .addOnFailureListener(e -> callback.onError("LOCATION_ERROR", e.getMessage()));
    }

    public boolean hasPermission() {
        boolean fine = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
        boolean coarse = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_COARSE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
        return fine || coarse;
    }

    private LocationRequest buildLocationRequest(String desiredAccuracy, float minDistance) {
        int priority = Priority.PRIORITY_HIGH_ACCURACY;
        if ("navigation".equals(desiredAccuracy)) {
            priority = Priority.PRIORITY_HIGH_ACCURACY;
        } else if ("medium".equals(desiredAccuracy)) {
            priority = Priority.PRIORITY_BALANCED_POWER_ACCURACY;
        } else if ("low".equals(desiredAccuracy) || "veryLow".equals(desiredAccuracy)) {
            priority = Priority.PRIORITY_LOW_POWER;
        } else if ("lowest".equals(desiredAccuracy)) {
            priority = Priority.PRIORITY_PASSIVE;
        }
        
        this.currentPriority = priority;
        
        return new LocationRequest.Builder(priority, config.locationUpdateInterval)
                .setMinUpdateIntervalMillis(config.fastestLocationUpdateInterval)
                .setMinUpdateDistanceMeters(minDistance)
                .build();
    }
}
