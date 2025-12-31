package dev.locus.storage;

import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;

import androidx.annotation.NonNull;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

public class QueueStore extends SQLiteOpenHelper {
    private static final String DB_NAME = "locus_queue.db";
    private static final int DB_VERSION = 1;

    public QueueStore(@NonNull Context context) {
        super(context, DB_NAME, null, DB_VERSION);
    }

    @Override
    public void onCreate(SQLiteDatabase db) {
        db.execSQL(
                "CREATE TABLE queue (" +
                        "id TEXT PRIMARY KEY," +
                        "created_at INTEGER," +
                        "payload TEXT," +
                        "retry_count INTEGER," +
                        "next_retry_at INTEGER," +
                        "idempotency_key TEXT," +
                        "type TEXT" +
                        ")"
        );
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        db.execSQL("DROP TABLE IF EXISTS queue");
        onCreate(db);
    }

    public String insertPayload(Map<String, Object> payload, String type, String idempotencyKey, int maxDays, int maxRecords) {
        String id = UUID.randomUUID().toString();
        long createdAt = System.currentTimeMillis();
        String payloadJson = new JSONObject(payload).toString();

        SQLiteDatabase db = getWritableDatabase();
        db.execSQL(
                "INSERT OR REPLACE INTO queue (id, created_at, payload, retry_count, next_retry_at, idempotency_key, type) " +
                        "VALUES (?, ?, ?, ?, ?, ?, ?)",
                new Object[]{
                        id,
                        createdAt,
                        payloadJson,
                        0,
                        null,
                        idempotencyKey,
                        type
                }
        );

        if (maxDays > 0) {
            pruneByAge(maxDays);
        }
        if (maxRecords > 0) {
            pruneByCount(maxRecords);
        }

        return id;
    }

    public List<Map<String, Object>> readQueue(int limit) {
        List<Map<String, Object>> results = new ArrayList<>();
        SQLiteDatabase db = getReadableDatabase();
        String limitValue = limit > 0 ? Integer.toString(limit) : null;
        Cursor cursor = db.query("queue", null, null, null, null, null, "created_at ASC", limitValue);
        try {
            while (cursor.moveToNext()) {
                Map<String, Object> record = new HashMap<>();
                record.put("id", cursor.getString(cursor.getColumnIndexOrThrow("id")));
                record.put("createdAt", cursor.getLong(cursor.getColumnIndexOrThrow("created_at")));
                record.put("payload", cursor.getString(cursor.getColumnIndexOrThrow("payload")));
                record.put("retryCount", cursor.getInt(cursor.getColumnIndexOrThrow("retry_count")));
                if (!cursor.isNull(cursor.getColumnIndexOrThrow("next_retry_at"))) {
                    record.put("nextRetryAt", cursor.getLong(cursor.getColumnIndexOrThrow("next_retry_at")));
                }
                record.put("idempotencyKey", cursor.getString(cursor.getColumnIndexOrThrow("idempotency_key")));
                record.put("type", cursor.getString(cursor.getColumnIndexOrThrow("type")));
                results.add(record);
            }
        } finally {
            cursor.close();
        }
        return results;
    }

    public void updateRetry(String id, int retryCount, long nextRetryAt) {
        SQLiteDatabase db = getWritableDatabase();
        db.execSQL(
                "UPDATE queue SET retry_count = ?, next_retry_at = ? WHERE id = ?",
                new Object[]{retryCount, nextRetryAt, id}
        );
    }

    public void deleteByIds(List<String> ids) {
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
        db.delete("queue", where.toString(), args);
    }

    public void clear() {
        SQLiteDatabase db = getWritableDatabase();
        db.execSQL("DELETE FROM queue");
    }

    public static Map<String, Object> parsePayload(String payloadJson) throws JSONException {
        Map<String, Object> payload = new HashMap<>();
        JSONObject json = new JSONObject(payloadJson);
        java.util.Iterator<String> keys = json.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            payload.put(key, json.get(key));
        }
        return payload;
    }

    private void pruneByAge(int maxDays) {
        long cutoff = System.currentTimeMillis() - (maxDays * 24L * 60L * 60L * 1000L);
        SQLiteDatabase db = getWritableDatabase();
        db.delete("queue", "created_at < ?", new String[]{Long.toString(cutoff)});
    }

    private void pruneByCount(int maxRecords) {
        SQLiteDatabase db = getWritableDatabase();
        db.execSQL(
                "DELETE FROM queue WHERE id IN (" +
                        "SELECT id FROM queue ORDER BY created_at DESC LIMIT -1 OFFSET ?" +
                        ")",
                new Object[]{maxRecords}
        );
    }
}
