package dev.locus.core;

import android.os.Handler;
import android.os.Looper;

import java.time.LocalTime;
import java.util.List;

public class Scheduler {

    private final ConfigManager config;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private Runnable scheduleRunnable;
    private long checkIntervalMs = 60000;
    private SchedulerListener listener;

    public interface SchedulerListener {
        boolean onScheduleCheck(boolean shouldBeEnabled);
    }

    public Scheduler(ConfigManager config, SchedulerListener listener) {
        this.config = config;
        this.listener = listener;
    }

    public void start() {
        if (!config.scheduleEnabled || scheduleRunnable != null) {
            return;
        }
        scheduleRunnable = new Runnable() {
            @Override
            public void run() {
                applyScheduleState();
                mainHandler.postDelayed(this, checkIntervalMs);
            }
        };
        mainHandler.post(scheduleRunnable);
    }

    public void stop() {
        if (scheduleRunnable != null) {
            mainHandler.removeCallbacks(scheduleRunnable);
            scheduleRunnable = null;
        }
    }

    public void applyScheduleState() {
        if (!config.scheduleEnabled || config.schedule == null || config.schedule.isEmpty()) {
            return;
        }
        boolean shouldEnable = isWithinScheduleWindow();
        if (listener != null) {
            listener.onScheduleCheck(shouldEnable);
        }
    }

    private boolean isWithinScheduleWindow() {
        LocalTime now = LocalTime.now();
        int nowMinutes = now.getHour() * 60 + now.getMinute();
        if (config.schedule == null) return false;
        
        for (String entry : config.schedule) {
            if (entry == null) {
                continue;
            }
            String[] parts = entry.split("-");
            if (parts.length != 2) {
                continue;
            }
            Integer start = parseMinutes(parts[0]);
            Integer end = parseMinutes(parts[1]);
            if (start == null || end == null) {
                continue;
            }
            if (end < start) {
                // Window crosses midnight
                if (nowMinutes >= start || nowMinutes < end) {
                    return true;
                }
            } else {
                if (nowMinutes >= start && nowMinutes < end) {
                    return true;
                }
            }
        }
        return false;
    }

    private Integer parseMinutes(String time) {
        try {
            String[] parts = time.split(":");
            if (parts.length == 2) {
                return Integer.parseInt(parts[0]) * 60 + Integer.parseInt(parts[1]);
            }
        } catch (NumberFormatException ignored) {
        }
        return null;
    }
}
