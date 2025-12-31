package dev.locus.storage;

import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.location.Location;

import androidx.annotation.NonNull;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

public class LocationStore extends SQLiteOpenHelper {
    private static final String DB_NAME = "locus.db";
    private static final int DB_VERSION = 2;

    public LocationStore(@NonNull Context context) {
        super(context, DB_NAME, null, DB_VERSION);
    }

    @Override
    public void onCreate(SQLiteDatabase db) {
        db.execSQL(
                "CREATE TABLE locations (" +
                        "id TEXT PRIMARY KEY," +
                        "timestamp INTEGER," +
                        "latitude REAL," +
                        "longitude REAL," +
                        "accuracy REAL," +
                        "speed REAL," +
                        "heading REAL," +
                        "altitude REAL," +
                        "is_moving INTEGER," +
                        "activity_type TEXT," +
                        "activity_confidence INTEGER," +
                        "event TEXT," +
                        "odometer REAL" +
                        ")"
        );
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        db.execSQL("DROP TABLE IF EXISTS locations");
        onCreate(db);
    }

    public void insertLocation(Location location, boolean isMoving, String activityType, int activityConfidence, String event, double odometer) {
        SQLiteDatabase db = getWritableDatabase();
        db.execSQL(
                "INSERT OR REPLACE INTO locations (id, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_moving, activity_type, activity_confidence, event, odometer) " +
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                new Object[]{
                        UUID.randomUUID().toString(),
                        location.getTime(),
                        location.getLatitude(),
                        location.getLongitude(),
                        location.getAccuracy(),
                        location.getSpeed(),
                        location.getBearing(),
                        location.getAltitude(),
                        isMoving ? 1 : 0,
                        activityType,
                        activityConfidence,
                        event,
                        odometer
                }
        );
    }

    public void clear() {
        SQLiteDatabase db = getWritableDatabase();
        db.execSQL("DELETE FROM locations");
    }

    public void insertPayload(Map<String, Object> payload, int maxDays, int maxRecords) {
        if (payload == null) {
            return;
        }
        Object coordsObj = payload.get("coords");
        if (!(coordsObj instanceof Map)) {
            return;
        }
        Map<String, Object> coords = (Map<String, Object>) coordsObj;
        double latitude = toDouble(coords.get("latitude"));
        double longitude = toDouble(coords.get("longitude"));
        double accuracy = toDouble(coords.get("accuracy"));
        double speed = toDouble(coords.get("speed"));
        double heading = toDouble(coords.get("heading"));
        double altitude = toDouble(coords.get("altitude"));

        String activityType = null;
        int activityConfidence = 0;
        Object activityObj = payload.get("activity");
        if (activityObj instanceof Map) {
            Map<String, Object> activity = (Map<String, Object>) activityObj;
            Object type = activity.get("type");
            if (type instanceof String) {
                activityType = (String) type;
            }
            Object confidence = activity.get("confidence");
            if (confidence instanceof Number) {
                activityConfidence = ((Number) confidence).intValue();
            }
        }

        long timestamp = System.currentTimeMillis();
        Object timestampValue = payload.get("timestamp");
        if (timestampValue instanceof String) {
            try {
                timestamp = Instant.parse((String) timestampValue).toEpochMilli();
            } catch (Exception ignored) {
            }
        }

        boolean isMoving = payload.get("is_moving") instanceof Boolean && (Boolean) payload.get("is_moving");
        String event = payload.get("event") instanceof String ? (String) payload.get("event") : null;
        double odometer = toDouble(payload.get("odometer"));

        SQLiteDatabase db = getWritableDatabase();
        db.execSQL(
                "INSERT OR REPLACE INTO locations (id, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_moving, activity_type, activity_confidence, event, odometer) " +
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                new Object[]{
                        UUID.randomUUID().toString(),
                        timestamp,
                        latitude,
                        longitude,
                        accuracy,
                        speed,
                        heading,
                        altitude,
                        isMoving ? 1 : 0,
                        activityType,
                        activityConfidence,
                        event,
                        odometer
                }
        );
        if (maxDays > 0) {
            pruneByAge(maxDays);
        }
        if (maxRecords > 0) {
            pruneByCount(maxRecords);
        }
    }

    public List<Map<String, Object>> readLocations(int limit) {
        List<Map<String, Object>> results = new ArrayList<>();
        SQLiteDatabase db = getReadableDatabase();
        String limitValue = limit > 0 ? Integer.toString(limit) : null;
        Cursor cursor = db.query("locations", null, null, null, null, null, "timestamp ASC", limitValue);
        try {
            while (cursor.moveToNext()) {
                Map<String, Object> record = new HashMap<>();
                record.put("id", cursor.getString(cursor.getColumnIndexOrThrow("id")));
                record.put("timestamp", cursor.getLong(cursor.getColumnIndexOrThrow("timestamp")));
                record.put("latitude", cursor.getDouble(cursor.getColumnIndexOrThrow("latitude")));
                record.put("longitude", cursor.getDouble(cursor.getColumnIndexOrThrow("longitude")));
                record.put("accuracy", cursor.getDouble(cursor.getColumnIndexOrThrow("accuracy")));
                record.put("speed", cursor.getDouble(cursor.getColumnIndexOrThrow("speed")));
                record.put("heading", cursor.getDouble(cursor.getColumnIndexOrThrow("heading")));
                record.put("altitude", cursor.getDouble(cursor.getColumnIndexOrThrow("altitude")));
                record.put("is_moving", cursor.getInt(cursor.getColumnIndexOrThrow("is_moving")) == 1);
                record.put("activity_type", cursor.getString(cursor.getColumnIndexOrThrow("activity_type")));
                record.put("activity_confidence", cursor.getInt(cursor.getColumnIndexOrThrow("activity_confidence")));
                record.put("event", cursor.getString(cursor.getColumnIndexOrThrow("event")));
                record.put("odometer", cursor.getDouble(cursor.getColumnIndexOrThrow("odometer")));
                results.add(record);
            }
        } finally {
            cursor.close();
        }
        return results;
    }

    public void deleteLocations(List<String> ids) {
        if (ids == null || ids.isEmpty()) {
            return;
        }
        SQLiteDatabase db = getWritableDatabase();
        StringBuilder where = new StringBuilder("id IN (");
        String[] args = new String[ids.size()];
        for (int i = 0; i < ids.size(); i++) {
            where.append("?");
            if (i < ids.size() - 1) {
                where.append(",");
            }
            args[i] = ids.get(i);
        }
        where.append(")");
        db.delete("locations", where.toString(), args);
    }

    private void pruneByAge(int maxDays) {
        long cutoff = System.currentTimeMillis() - (maxDays * 24L * 60L * 60L * 1000L);
        SQLiteDatabase db = getWritableDatabase();
        db.delete("locations", "timestamp < ?", new String[]{Long.toString(cutoff)});
    }

    private void pruneByCount(int maxRecords) {
        SQLiteDatabase db = getWritableDatabase();
        db.execSQL(
                "DELETE FROM locations WHERE id IN (" +
                        "SELECT id FROM locations ORDER BY timestamp DESC LIMIT -1 OFFSET ?" +
                        ")",
                new Object[]{maxRecords}
        );
    }

    private double toDouble(Object value) {
        if (value instanceof Number) {
            return ((Number) value).doubleValue();
        }
        return 0.0;
    }
}
