package dev.locus.storage;

import android.content.ContentValues;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import dev.locus.LocusPlugin;

public class LogStore {

    private static final String KEY_LOG = "bg_log";
    private static final String KEY_LOG_MIGRATED = "bg_log_migrated";
    private static final String DB_NAME = "locus_logs.db";
    private static final int DB_VERSION = 1;
    private static final String TABLE_LOGS = "logs";

    private final SharedPreferences prefs;
    private final LogDbHelper dbHelper;

    private static class LogDbHelper extends SQLiteOpenHelper {
        LogDbHelper(Context context) {
            super(context, DB_NAME, null, DB_VERSION);
        }

        @Override
        public void onCreate(SQLiteDatabase db) {
            db.execSQL("CREATE TABLE IF NOT EXISTS " + TABLE_LOGS + " (" +
                    "id INTEGER PRIMARY KEY AUTOINCREMENT," +
                    "timestamp INTEGER NOT NULL," +
                    "level TEXT NOT NULL," +
                    "message TEXT NOT NULL," +
                    "tag TEXT" +
                    ")");
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON " + TABLE_LOGS + " (timestamp)");
        }

        @Override
        public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
            // No-op for now.
        }
    }

    public LogStore(Context context) {
        prefs = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);
        dbHelper = new LogDbHelper(context);
        migrateLegacyLog();
    }

    public void append(String level, String message, int maxDays) {
        SQLiteDatabase db = dbHelper.getWritableDatabase();
        ContentValues values = new ContentValues();
        values.put("timestamp", System.currentTimeMillis());
        values.put("level", level);
        values.put("message", message);
        values.put("tag", "locus");
        db.insert(TABLE_LOGS, null, values);
        if (maxDays > 0) {
            pruneByAge(db, maxDays);
        }
    }

    public List<Map<String, Object>> readEntries(int limit) {
        List<Map<String, Object>> entries = new ArrayList<>();
        SQLiteDatabase db = dbHelper.getReadableDatabase();
        String orderBy = "timestamp DESC";
        String limitClause = limit > 0 ? String.valueOf(limit) : null;
        Cursor cursor = db.query(TABLE_LOGS, new String[]{"timestamp", "level", "message", "tag"},
                null, null, null, null, orderBy, limitClause);
        try {
            while (cursor.moveToNext()) {
                Map<String, Object> entry = new HashMap<>();
                entry.put("timestamp", cursor.getLong(0));
                entry.put("level", cursor.getString(1));
                entry.put("message", cursor.getString(2));
                String tag = cursor.getString(3);
                if (tag != null) {
                    entry.put("tag", tag);
                }
                entries.add(entry);
            }
        } finally {
            cursor.close();
        }
        return entries;
    }

    private void pruneByAge(SQLiteDatabase db, int maxDays) {
        long cutoff = System.currentTimeMillis() - (maxDays * 24L * 60L * 60L * 1000L);
        db.delete(TABLE_LOGS, "timestamp < ?", new String[]{String.valueOf(cutoff)});
    }

    private void migrateLegacyLog() {
        if (prefs.getBoolean(KEY_LOG_MIGRATED, false)) {
            return;
        }
        String existing = prefs.getString(KEY_LOG, "");
        if (existing != null && !existing.isEmpty()) {
            String[] lines = existing.split("\n");
            SQLiteDatabase db = dbHelper.getWritableDatabase();
            for (String line : lines) {
                int idx = line.indexOf('|');
                if (idx <= 0) {
                    continue;
                }
                String[] parts = line.split("\\|", 3);
                if (parts.length < 3) {
                    continue;
                }
                long timestamp;
                try {
                    timestamp = Long.parseLong(parts[0]);
                } catch (NumberFormatException e) {
                    continue;
                }
                ContentValues values = new ContentValues();
                values.put("timestamp", timestamp);
                values.put("level", parts[1]);
                values.put("message", parts[2]);
                values.put("tag", "locus");
                db.insert(TABLE_LOGS, null, values);
            }
        }
        prefs.edit().remove(KEY_LOG).putBoolean(KEY_LOG_MIGRATED, true).apply();
    }
}
