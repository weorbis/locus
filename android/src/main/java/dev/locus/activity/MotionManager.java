package dev.locus.activity;

import android.annotation.SuppressLint;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.google.android.gms.location.ActivityRecognition;
import com.google.android.gms.location.ActivityRecognitionClient;
import com.google.android.gms.tasks.Task;

import java.util.List;

import dev.locus.core.ConfigManager;
import dev.locus.receiver.ActivityRecognizedBroadcastReceiver;

public class MotionManager {

    private static final String TAG = "locus.MotionManager";
    private final Context context;
    private final ConfigManager config;
    private final ActivityRecognitionClient activityClient;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private PendingIntent activityPendingIntent;
    private Runnable stopTimeoutRunnable;
    private Runnable motionTriggerRunnable;
    private String lastActivityType = "unknown";
    private int lastActivityConfidence = 0;
    private boolean isMoving = false;
    
    private MotionListener listener;

    public interface MotionListener {
        void onMotionChange(boolean isMoving);
        void onActivityChange(String type, int confidence);
    }

    public MotionManager(Context context, ConfigManager config) {
        this.context = context;
        this.config = config;
        this.activityClient = ActivityRecognition.getClient(context);
    }
    
    public void setListener(MotionListener listener) {
        this.listener = listener;
    }
    
    public boolean isMoving() {
        return isMoving;
    }
    
    public String getLastActivityType() {
        return lastActivityType;
    }
    
    public int getLastActivityConfidence() {
        return lastActivityConfidence;
    }

    @SuppressLint("MissingPermission")
    public void start() {
        if (config.disableMotionActivityUpdates) {
            return;
        }
        activityPendingIntent = createActivityPendingIntent();
        Task<Void> task = activityClient.requestActivityUpdates(config.activityRecognitionInterval, activityPendingIntent);
        task.addOnFailureListener(e -> Log.e(TAG, "Activity recognition failed: " + e.getMessage()));
        Log.i(TAG, "Activity recognition started");
    }

    public void stop() {
        cancelStopTimeout();
        cancelMotionTrigger();
        if (activityPendingIntent != null) {
            activityClient.removeActivityUpdates(activityPendingIntent);
            activityPendingIntent = null;
            Log.i(TAG, "Activity recognition stopped");
        }
    }
    
    public void setPace(boolean moving) {
        setMovingState(moving);
    }

    public void onActivityEvent(String type, int confidence) {
        if (confidence < config.minActivityConfidence) {
            return;
        }
        lastActivityType = type;
        lastActivityConfidence = confidence;
        
        if (listener != null) {
            listener.onActivityChange(type, confidence);
        }

        boolean nextMoving = isMovingActivity(type);
        if (!nextMoving && config.disableStopDetection) {
            return;
        }
        
        scheduleMotionTransition(nextMoving);
    }

    private void scheduleMotionTransition(boolean moving) {
        if (moving) {
            cancelStopTimeout();
            cancelMotionTrigger();
            if (!isMoving) {
                if (config.motionTriggerDelay > 0) {
                    motionTriggerRunnable = () -> setMovingState(true);
                    mainHandler.postDelayed(motionTriggerRunnable, config.motionTriggerDelay);
                } else {
                    setMovingState(true);
                }
            }
        } else {
            cancelMotionTrigger();
            if (config.stopTimeoutMinutes > 0) {
                long delayMs = config.stopTimeoutMinutes * 60L * 1000L;
                scheduleStopTimeout(delayMs);
            } else if (config.stopDetectionDelay > 0) {
                scheduleStopTimeout(config.stopDetectionDelay);
            } else {
                setMovingState(false);
            }
        }
    }

    private void setMovingState(boolean moving) {
        if (isMoving == moving) {
            return;
        }
        isMoving = moving;
        if (listener != null) {
            listener.onMotionChange(moving);
        }
    }

    private void scheduleStopTimeout(long delayMs) {
        cancelStopTimeout();
        stopTimeoutRunnable = () -> setMovingState(false);
        mainHandler.postDelayed(stopTimeoutRunnable, delayMs);
    }

    private void cancelStopTimeout() {
        if (stopTimeoutRunnable != null) {
            mainHandler.removeCallbacks(stopTimeoutRunnable);
            stopTimeoutRunnable = null;
        }
    }

    private void cancelMotionTrigger() {
        if (motionTriggerRunnable != null) {
            mainHandler.removeCallbacks(motionTriggerRunnable);
            motionTriggerRunnable = null;
        }
    }

    private boolean isMovingActivity(String activityType) {
        if (!config.triggerActivities.isEmpty()) {
            return config.triggerActivities.contains(activityType);
        }
        return "walking".equals(activityType)
                || "running".equals(activityType)
                || "onFoot".equals(activityType)
                || "inVehicle".equals(activityType)
                || "onBicycle".equals(activityType);
    }

    private PendingIntent createActivityPendingIntent() {
        Intent intent = new Intent(context, ActivityRecognizedBroadcastReceiver.class);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 31) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        return PendingIntent.getBroadcast(context, 0, intent, flags);
    }
}
