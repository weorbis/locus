package dev.locus.location

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import dev.locus.core.ConfigManager

class LocationClient(
    private val context: Context,
    private val config: ConfigManager
) {
    private val fusedLocationClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    private var locationCallback: LocationCallback? = null
    private var locationRequest: LocationRequest? = null
    private var listener: LocationClientListener? = null
    private var currentPositionCts: CancellationTokenSource? = null

    // State
    private var currentPriority: Int = Priority.PRIORITY_HIGH_ACCURACY

    interface LocationClientListener {
        fun onLocation(location: Location)
        fun onLocationError(code: String, message: String)
    }

    fun interface LocationResultCallback {
        fun onSuccess(location: Location)
        fun onError(code: String, message: String) {}
    }

    fun setListener(listener: LocationClientListener?) {
        this.listener = listener
    }

    @SuppressLint("MissingPermission")
    fun start() {
        if (!hasPermission()) {
            listener?.onLocationError("PERMISSION_DENIED", "Location permission missing")
            return
        }

        stop()

        locationRequest = buildLocationRequest(config.desiredAccuracy, config.stationaryRadius)
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    listener?.onLocation(location)
                }
            }
        }

        fusedLocationClient.requestLocationUpdates(
            locationRequest!!,
            locationCallback!!,
            Looper.getMainLooper()
        )
        Log.i(TAG, "Location updates started")
    }

    fun stop() {
        currentPositionCts?.cancel()
        currentPositionCts = null
        locationCallback?.let { callback ->
            fusedLocationClient.removeLocationUpdates(callback)
            locationCallback = null
            Log.i(TAG, "Location updates stopped")
        }
    }

    @SuppressLint("MissingPermission")
    fun updateRequest(isMoving: Boolean) {
        locationCallback ?: return

        val minDistance = if (isMoving) config.distanceFilter else config.stationaryRadius
        val newRequest = buildLocationRequest(config.desiredAccuracy, minDistance)

        fusedLocationClient.removeLocationUpdates(locationCallback!!)
        fusedLocationClient.requestLocationUpdates(
            newRequest,
            locationCallback!!,
            Looper.getMainLooper()
        )

        Log.i(TAG, "Location request updated. Moving: $isMoving, Distance: $minDistance")
    }

    @SuppressLint("MissingPermission")
    fun getCurrentPosition(callback: LocationResultCallback) {
        if (!hasPermission()) {
            callback.onError("PERMISSION_DENIED", "Location permission not granted")
            return
        }

        // Cancel any in-flight single-location request
        currentPositionCts?.cancel()
        val cts = CancellationTokenSource()
        currentPositionCts = cts
        fusedLocationClient.getCurrentLocation(currentPriority, cts.token)
            .addOnSuccessListener { location ->
                currentPositionCts = null
                if (location == null) {
                    callback.onError("LOCATION_ERROR", "No location available")
                } else {
                    callback.onSuccess(location)
                }
            }
            .addOnFailureListener { e ->
                currentPositionCts = null
                callback.onError("LOCATION_ERROR", e.message ?: "Unknown error")
            }
    }

    fun hasPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val coarse = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        return fine || coarse
    }

    private fun buildLocationRequest(desiredAccuracy: String?, minDistance: Float): LocationRequest {
        val priority = when (desiredAccuracy) {
            "navigation" -> Priority.PRIORITY_HIGH_ACCURACY
            "medium" -> Priority.PRIORITY_BALANCED_POWER_ACCURACY
            "low", "veryLow" -> Priority.PRIORITY_LOW_POWER
            "lowest" -> Priority.PRIORITY_PASSIVE
            else -> Priority.PRIORITY_HIGH_ACCURACY
        }

        currentPriority = priority

        return LocationRequest.Builder(priority, config.locationUpdateInterval)
            .setMinUpdateIntervalMillis(config.fastestLocationUpdateInterval)
            .setMinUpdateDistanceMeters(minDistance)
            .build()
    }

    companion object {
        private const val TAG = "locus.LocationClient"
    }
}
