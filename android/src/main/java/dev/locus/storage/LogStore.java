package dev.locus.storage;

import android.content.Context;
import android.content.SharedPreferences;

import dev.locus.LocusPlugin;

public class LogStore {

    private static final String KEY_LOG = "bg_log";
    private static final int MAX_SIZE = 50000;

    private final SharedPreferences prefs;

    public LogStore(Context context) {
        prefs = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);
    }

    public void append(String level, String line, int maxDays) {
        String existing = prefs.getString(KEY_LOG, "");
        String entry = System.currentTimeMillis() + "|" + level + "|" + line;
        String next = existing.isEmpty() ? entry : existing + "\n" + entry;
        if (maxDays > 0) {
            next = pruneByAge(next, maxDays);
        }
        if (next.length() > MAX_SIZE) {
            next = next.substring(next.length() - MAX_SIZE);
        }
        prefs.edit().putString(KEY_LOG, next).apply();
    }

    public String read() {
        return prefs.getString(KEY_LOG, "");
    }

    private String pruneByAge(String log, int maxDays) {
        long cutoff = System.currentTimeMillis() - (maxDays * 24L * 60L * 60L * 1000L);
        String[] lines = log.split("\n");
        StringBuilder builder = new StringBuilder();
        for (String line : lines) {
            int idx = line.indexOf('|');
            if (idx <= 0) {
                continue;
            }
            try {
                long timestamp = Long.parseLong(line.substring(0, idx));
                if (timestamp >= cutoff) {
                    if (builder.length() > 0) {
                        builder.append("\n");
                    }
                    builder.append(line);
                }
            } catch (NumberFormatException e) {
                // Skip malformed entries.
            }
        }
        return builder.toString();
    }
}
