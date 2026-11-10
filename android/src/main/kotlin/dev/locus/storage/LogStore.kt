package dev.locus.storage

import android.content.ContentValues
import android.content.Context
import net.zetetic.database.sqlcipher.SQLiteDatabase
import net.zetetic.database.sqlcipher.SQLiteOpenHelper
import dev.locus.LocusPlugin

class LogStore(private val context: Context) {

    private val prefs = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE)
    private val dbHelper = LazyHelper(context, ::LogDbHelper)

    /** Opens the log database, importing the legacy preferences log the first time. */
    private fun database(): SQLiteDatabase {
        val db = dbHelper.get().writableDatabase
        migrateLegacyLog(db)
        return db
    }

    /** Never waits for storage preparation: queued until the encrypted store is ready, dropped if it is unavailable. */
    fun append(level: String, message: String, maxDays: Int) {
        EncryptedStorage.runWhenReady(context) { appendNow(level, message, maxDays) }
    }

    private fun appendNow(level: String, message: String, maxDays: Int) {
        val db = database()
        val values = ContentValues().apply {
            put("timestamp", System.currentTimeMillis())
            put("level", level)
            put("message", message)
            put("tag", TAG)
        }
        db.insert(TABLE_LOGS, null, values)

        if (maxDays > 0) {
            pruneByAge(db, maxDays)
        }
    }

    fun readEntries(limit: Int): List<Map<String, Any>> {
        val entries = mutableListOf<Map<String, Any>>()
        val limitClause = if (limit > 0) limit.toString() else null

        database().query(
            TABLE_LOGS,
            arrayOf("timestamp", "level", "message", "tag"),
            null,
            null,
            null,
            null,
            "timestamp DESC",
            limitClause
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val entry = mutableMapOf<String, Any>(
                    "timestamp" to cursor.getLong(0),
                    "level" to cursor.getString(1),
                    "message" to cursor.getString(2)
                )
                cursor.getString(3)?.let { tag ->
                    entry["tag"] = tag
                }
                entries.add(entry)
            }
        }
        return entries
    }

    private fun pruneByAge(db: SQLiteDatabase, maxDays: Int) {
        val cutoff = System.currentTimeMillis() - (maxDays * 24L * 60L * 60L * 1000L)
        db.delete(TABLE_LOGS, "timestamp < ?", arrayOf(cutoff.toString()))
    }

    private fun migrateLegacyLog(db: SQLiteDatabase) {
        if (prefs.getBoolean(KEY_LOG_MIGRATED, false)) return

        prefs.getString(KEY_LOG, "")?.takeIf { it.isNotEmpty() }?.let { existing ->
            existing.split("\n").forEach { line ->
                val parts = line.split("|", limit = 3)
                if (parts.size >= 3) {
                    val timestamp = parts[0].toLongOrNull() ?: return@forEach
                    val values = ContentValues().apply {
                        put("timestamp", timestamp)
                        put("level", parts[1])
                        put("message", parts[2])
                        put("tag", TAG)
                    }
                    db.insert(TABLE_LOGS, null, values)
                }
            }
        }

        prefs.edit()
            .remove(KEY_LOG)
            .putBoolean(KEY_LOG_MIGRATED, true)
            .apply()
    }

    private class LogDbHelper(context: EncryptedDatabaseContext) : SQLiteOpenHelper(
        context,
        DB_NAME,
        context.password,
        null,
        DB_VERSION,
        EncryptedStorage.MINIMUM_SUPPORTED_VERSION,
        EncryptedStorage.errorHandler,
        null,
        false
    ) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS $TABLE_LOGS (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    level TEXT NOT NULL,
                    message TEXT NOT NULL,
                    tag TEXT
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON $TABLE_LOGS (timestamp)")
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            // No-op for now.
        }
    }

    companion object {
        private const val KEY_LOG = "bg_log"
        private const val KEY_LOG_MIGRATED = "bg_log_migrated"
        private const val DB_NAME = "locus_logs.db"
        private const val DB_VERSION = 1
        private const val TABLE_LOGS = "logs"
        private const val TAG = "locus"
    }
}
