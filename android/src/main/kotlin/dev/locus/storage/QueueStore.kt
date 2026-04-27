package dev.locus.storage

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONException
import org.json.JSONObject
import java.util.UUID

class QueueStore(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

    override fun onConfigure(db: SQLiteDatabase) {
        // Durability: WAL keeps the journal independent of the main DB, and
        // synchronous=FULL fsyncs both files on commit. Together they survive
        // process kills between commit and checkpoint without data loss.
        db.execSQL("PRAGMA journal_mode=WAL")
        db.execSQL("PRAGMA synchronous=FULL")
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE queue (
                id TEXT PRIMARY KEY,
                created_at INTEGER,
                payload TEXT,
                retry_count INTEGER,
                next_retry_at INTEGER,
                idempotency_key TEXT,
                type TEXT
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Preserve data across schema upgrades.
        // Add migration steps for each version increment here.
        // Example: if (oldVersion < 2) { db.execSQL("ALTER TABLE queue ADD COLUMN new_col TEXT") }
        // Only drop and recreate as last resort.
    }

    fun insertPayload(
        payload: Map<String, Any>,
        type: String?,
        idempotencyKey: String?,
        maxDays: Int,
        maxRecords: Int
    ): String {
        val id = UUID.randomUUID().toString()
        val createdAt = System.currentTimeMillis()
        val payloadJson = JSONObject(payload).toString()

        try {
            val db = writableDatabase
            db.beginTransaction()
            try {
                db.execSQL(
                    """
                    INSERT OR REPLACE INTO queue
                    (id, created_at, payload, retry_count, next_retry_at, idempotency_key, type)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """.trimIndent(),
                    arrayOf(id, createdAt, payloadJson, 0, null, idempotencyKey, type)
                )

                if (maxDays > 0) pruneByAge(maxDays)
                if (maxRecords > 0) pruneByCount(maxRecords)
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
            checkpoint(db)
        } catch (e: Exception) {
            android.util.Log.e("QueueStore", "Failed to insert queue payload: ${e.message}", e)
        }

        return id
    }

    fun readQueue(limit: Int): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val limitValue = if (limit > 0) limit.toString() else null

        try {
            readableDatabase.query(
                "queue",
                null,
                null,
                null,
                null,
                null,
                "created_at ASC",
                limitValue
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val record = mutableMapOf<String, Any>(
                        "id" to cursor.getString(cursor.getColumnIndexOrThrow("id")),
                        "createdAt" to cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
                        "payload" to cursor.getString(cursor.getColumnIndexOrThrow("payload")),
                        "retryCount" to cursor.getInt(cursor.getColumnIndexOrThrow("retry_count")),
                        "idempotencyKey" to cursor.getString(cursor.getColumnIndexOrThrow("idempotency_key")),
                        "type" to cursor.getString(cursor.getColumnIndexOrThrow("type"))
                    )

                    val nextRetryAtIndex = cursor.getColumnIndexOrThrow("next_retry_at")
                    if (!cursor.isNull(nextRetryAtIndex)) {
                        record["nextRetryAt"] = cursor.getLong(nextRetryAtIndex)
                    }

                    results.add(record)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("QueueStore", "Failed to read queue: ${e.message}", e)
        }
        return results
    }

    fun updateRetry(id: String, retryCount: Int, nextRetryAt: Long) {
        try {
            val db = writableDatabase
            db.execSQL(
                "UPDATE queue SET retry_count = ?, next_retry_at = ? WHERE id = ?",
                arrayOf(retryCount, nextRetryAt, id)
            )
            checkpoint(db)
        } catch (e: Exception) {
            android.util.Log.e("QueueStore", "Failed to update retry: ${e.message}", e)
        }
    }

    fun deleteByIds(ids: List<String>?) {
        if (ids.isNullOrEmpty()) return

        try {
            val db = writableDatabase
            val placeholders = ids.joinToString(",") { "?" }
            db.delete("queue", "id IN ($placeholders)", ids.toTypedArray())
            checkpoint(db)
        } catch (e: Exception) {
            android.util.Log.e("QueueStore", "Failed to delete queue items: ${e.message}", e)
        }
    }

    fun clear() {
        try {
            val db = writableDatabase
            db.execSQL("DELETE FROM queue")
            checkpoint(db)
        } catch (e: Exception) {
            android.util.Log.e("QueueStore", "Failed to clear queue: ${e.message}", e)
        }
    }

    private fun pruneByAge(maxDays: Int) {
        val cutoff = System.currentTimeMillis() - (maxDays * 24L * 60L * 60L * 1000L)
        writableDatabase.delete("queue", "created_at < ?", arrayOf(cutoff.toString()))
    }

    private fun pruneByCount(maxRecords: Int) {
        writableDatabase.execSQL(
            """
            DELETE FROM queue WHERE id IN (
                SELECT id FROM queue ORDER BY created_at DESC LIMIT -1 OFFSET ?
            )
            """.trimIndent(),
            arrayOf(maxRecords)
        )
    }

    /**
     * Bound the WAL file size after a write transaction. PASSIVE never blocks
     * readers and is a no-op if no work is needed; the DB stays durable either
     * way thanks to synchronous=FULL.
     */
    private fun checkpoint(db: SQLiteDatabase) {
        try {
            db.rawQuery("PRAGMA wal_checkpoint(PASSIVE)", null).use { it.moveToFirst() }
        } catch (e: Exception) {
            android.util.Log.w("QueueStore", "wal_checkpoint failed: ${e.message}")
        }
    }

    companion object {
        private const val DB_NAME = "locus_queue.db"
        private const val DB_VERSION = 1

        @Throws(JSONException::class)
        fun parsePayload(payloadJson: String): Map<String, Any> {
            val json = JSONObject(payloadJson)
            return json.keys().asSequence().associateWith { key -> json.get(key) }
        }
    }
}
