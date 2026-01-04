package dev.locus.core;

import android.content.Context;
import android.os.PowerManager;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

public class BackgroundTaskManager {
    private static final String TAG = "locus";

    private final PowerManager powerManager;
    private final AtomicInteger taskCounter = new AtomicInteger(1);
    private final Map<Integer, PowerManager.WakeLock> tasks = new HashMap<>();

    public BackgroundTaskManager(Context context) {
        this.powerManager = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
    }

    public int start() {
        if (powerManager == null) {
            return 0;
        }
        if (tasks.size() > 50) {
            release(); // defensive cleanup to avoid unbounded wake locks
        }
        int taskId = taskCounter.getAndIncrement();
        PowerManager.WakeLock wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                TAG + ":bgTask:" + taskId
        );
        wakeLock.acquire(10 * 60 * 1000L);
        tasks.put(taskId, wakeLock);
        return taskId;
    }

    public void stop(int taskId) {
        PowerManager.WakeLock wakeLock = tasks.remove(taskId);
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
    }

    public void release() {
        for (PowerManager.WakeLock wakeLock : tasks.values()) {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
            }
        }
        tasks.clear();
    }
}
