package dev.locus.storage

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteCursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.location.Location
import java.time.Instant
import java.util.UUID

class LocationStore(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

    override fun onConfigure(db: SQLiteDatabase) {
        // Durability: WAL keeps the journal independent of the main DB, and
        // synchronous=FULL fsyncs both files on commit. Together they survive
        // process kills between commit and checkpoint without data loss.
        //
        // Use rawQuery instead of execSQL: Samsung's hardened SQLite (seen on
        // SM A346E / Android 16) treats `PRAGMA journal_mode=WAL` as a query
        // because it returns the resulting mode, and rejects it from execSQL
        // with "Queries can be performed using SQLiteDatabase query or
        // rawQuery methods only." rawQuery works on AOSP and Samsung alike.
        db.rawQuery("PRAGMA journal_mode=WAL", null).use { it.moveToFirst() }
        db.rawQuery("PRAGMA synchronous=FULL", null).use { it.moveToFirst() }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE locations (
                id TEXT PRIMARY KEY,
                timestamp INTEGER,
                latitude REAL,
                longitude REAL,
                accuracy REAL,
                speed REAL,
                heading REAL,
                altitude REAL,
                is_moving INTEGER,
                activity_type TEXT,
                activity_confidence INTEGER,
                event TEXT,
                odometer REAL,
                extras_json TEXT
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 3) {
            db.execSQL("ALTER TABLE locations ADD COLUMN extras_json TEXT")
        }
    }

    fun insertLocation(
        location: Location,
        isMoving: Boolean,
        activityType: String?,
        activityConfidence: Int,
        event: String?,
        odometer: Double
    ) {
        val values = ContentValues().apply {
            put("id", UUID.randomUUID().toString())
            put("timestamp", location.time)
            put("latitude", location.latitude)
            put("longitude", location.longitude)
            put("accuracy", location.accuracy)
            put("speed", location.speed)
            put("heading", location.bearing)
            put("altitude", location.altitude)
            put("is_moving", if (isMoving) 1 else 0)
            put("activity_type", activityType)
            put("activity_confidence", activityConfidence)
            put("event", event)
            put("odometer", odometer)
        }

        try {
            val db = writableDatabase
            db.insertWithOnConflict("locations", null, values, SQLiteDatabase.CONFLICT_REPLACE)
            checkpoint(db)
        } catch (e: Exception) {
            android.util.Log.e("LocationStore", "Failed to insert location: ${e.message}", e)
        }
    }

    fun clear() {
        try {
            val db = writableDatabase
            db.execSQL("DELETE FROM locations")
            checkpoint(db)
        } catch (e: Exception) {
            android.util.Log.e("LocationStore", "Failed to clear locations: ${e.message}", e)
        }
    }

    fun insertPayload(payload: Map<String, Any>?, maxDays: Int, maxRecords: Int) {
        if (payload == null) return

        try {
            val coords = payload["coords"] as? Map<*, *> ?: return
            val latitude = coords["latitude"].toDoubleOrZero()
            val longitude = coords["longitude"].toDoubleOrZero()
            val accuracy = coords["accuracy"].toDoubleOrZero()
            val speed = coords["speed"].toDoubleOrZero()
            val heading = coords["heading"].toDoubleOrZero()
            val altitude = coords["altitude"].toDoubleOrZero()

            val activity = payload["activity"] as? Map<*, *>
            val activityType = activity?.get("type") as? String
            val activityConfidence = (activity?.get("confidence") as? Number)?.toInt() ?: 0

            val timestamp = (payload["timestamp"] as? String)?.let { timestampStr ->
                runCatching { Instant.parse(timestampStr).toEpochMilli() }.getOrNull()
            } ?: System.currentTimeMillis()

            val isMoving = payload["is_moving"] as? Boolean ?: false
            val event = payload["event"] as? String
            val odometer = payload["odometer"].toDoubleOrZero()
            val extrasJson = (payload["extras"] as? Map<*, *>)?.let { extras ->
                org.json.JSONObject(extras).toString()
            }

            val values = ContentValues().apply {
                put("id", UUID.randomUUID().toString())
                put("timestamp", timestamp)
                put("latitude", latitude)
                put("longitude", longitude)
                put("accuracy", accuracy)
                put("speed", speed)
                put("heading", heading)
                put("altitude", altitude)
                put("is_moving", if (isMoving) 1 else 0)
                put("activity_type", activityType)
                put("activity_confidence", activityConfidence)
                put("event", event)
                put("odometer", odometer)
                put("extras_json", extrasJson)
            }

            val db = writableDatabase
            db.beginTransaction()
            try {
                db.insertWithOnConflict("locations", null, values, SQLiteDatabase.CONFLICT_REPLACE)

                if (maxDays > 0) pruneByAge(maxDays)
                if (maxRecords > 0) pruneByCount(maxRecords)
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
            checkpoint(db)
        } catch (e: Exception) {
            android.util.Log.e("LocationStore", "Failed to insert payload: ${e.message}", e)
        }
    }

    fun readLocations(limit: Int): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val limitValue = if (limit > 0) limit.toString() else null

        try {
            readableDatabase.query(
                "locations",
                null,
                null,
                null,
                null,
                null,
                "timestamp ASC",
                limitValue
            ).use { cursor ->
                val columns = LocationColumns(cursor)
                while (cursor.moveToNext()) {
                    results.add(columns.read(cursor))
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("LocationStore", "Failed to read locations: ${e.message}", e)
        }
        return results
    }

    /** Apply every predicate before ordering and paging; read errors propagate to the caller. */
    internal fun queryLocations(query: StoredLocationQuery): List<Map<String, Any>> {
        if (query.limit?.let { it <= 0L } == true || query.bounds?.hasNaN == true) {
            return emptyList()
        }

        // Match Cursor's null-to-zero conversion and Dart's invalid-coordinate fallback.
        val latitude = "COALESCE(latitude, 0)"
        val longitude = "COALESCE(longitude, 0)"
        val invalidCoords = "($latitude < -90 OR $latitude > 90 OR $longitude < -180 OR $longitude > 180)"
        val normalizedLatitude = "CASE WHEN $invalidCoords THEN 0 ELSE $latitude END"
        val normalizedLongitude = "CASE WHEN $invalidCoords THEN 0 ELSE $longitude END"
        val accuracy = "CASE WHEN $invalidCoords THEN -1 ELSE COALESCE(accuracy, 0) END"
        val predicates = mutableListOf<String>()
        val bindings = mutableListOf<Number>()
        fun predicate(sql: String, value: Number) {
            predicates.add(sql)
            bindings.add(value)
        }

        query.from?.let { micros ->
            val millis = Math.floorDiv(micros, MICROS_PER_MILLISECOND)
            val roundUp = if (Math.floorMod(micros, MICROS_PER_MILLISECOND) == 0L) 0L else 1L
            predicate("COALESCE(timestamp, 0) >= ?", millis + roundUp)
        }
        query.to?.let { predicate("COALESCE(timestamp, 0) <= ?", Math.floorDiv(it, MICROS_PER_MILLISECOND)) }
        query.minAccuracy?.takeUnless { it.isNaN() }?.let { predicate("($accuracy) <= ?", it) }
        query.maxAccuracy?.takeUnless { it.isNaN() }?.let { predicate("($accuracy) >= ?", it) }
        query.isMoving?.let { predicate("CASE WHEN is_moving = 1 THEN 1 ELSE 0 END = ?", if (it) 1L else 0L) }
        query.bounds?.let { bounds ->
            predicates.add("($normalizedLatitude) BETWEEN ? AND ?")
            bindings.addAll(listOf(bounds.south, bounds.north))
            predicates.add("($normalizedLongitude) BETWEEN ? AND ?")
            bindings.addAll(listOf(bounds.west, bounds.east))
        }
        val direction = if (query.oldestFirst) "ASC" else "DESC"
        val selection = if (predicates.isEmpty()) "" else " WHERE ${predicates.joinToString(" AND ")}"
        val sql = "SELECT * FROM locations$selection ORDER BY COALESCE(timestamp, 0) $direction, rowid ASC LIMIT ? OFFSET ?"
        bindings.add(query.limit ?: -1L)
        bindings.add(query.offset)
        val records = mutableListOf<Map<String, Any>>()
        // Bind numerically: string selectionArgs would change comparison affinity for CASE
        // expressions, and string conversion would lose IEEE infinity semantics.
        readableDatabase.rawQueryWithFactory({ _, driver, editTable, statement ->
            bindings.forEachIndexed { index, value ->
                when (value) {
                    is Double -> statement.bindDouble(index + 1, value)
                    else -> statement.bindLong(index + 1, value.toLong())
                }
            }
            SQLiteCursor(driver, editTable, statement)
        }, sql, emptyArray(), "locations").use { cursor ->
            val columns = LocationColumns(cursor)
            while (cursor.moveToNext()) records.add(columns.read(cursor))
        }
        return records
    }

    private class LocationColumns(cursor: Cursor) {
        private val id = cursor.getColumnIndexOrThrow("id")
        private val timestamp = cursor.getColumnIndexOrThrow("timestamp")
        private val latitude = cursor.getColumnIndexOrThrow("latitude")
        private val longitude = cursor.getColumnIndexOrThrow("longitude")
        private val accuracy = cursor.getColumnIndexOrThrow("accuracy")
        private val speed = cursor.getColumnIndexOrThrow("speed")
        private val heading = cursor.getColumnIndexOrThrow("heading")
        private val altitude = cursor.getColumnIndexOrThrow("altitude")
        private val isMoving = cursor.getColumnIndexOrThrow("is_moving")
        private val activityConfidence = cursor.getColumnIndexOrThrow("activity_confidence")
        private val odometer = cursor.getColumnIndexOrThrow("odometer")
        private val activityType = cursor.getColumnIndexOrThrow("activity_type")
        private val event = cursor.getColumnIndexOrThrow("event")
        private val extrasJson = cursor.getColumnIndexOrThrow("extras_json")

        fun read(cursor: Cursor): Map<String, Any> {
            val record = mutableMapOf<String, Any>(
                "id" to cursor.getString(id),
                "timestamp" to cursor.getLong(timestamp),
                "latitude" to cursor.getDouble(latitude),
                "longitude" to cursor.getDouble(longitude),
                "accuracy" to cursor.getDouble(accuracy),
                "speed" to cursor.getDouble(speed),
                "heading" to cursor.getDouble(heading),
                "altitude" to cursor.getDouble(altitude),
                "is_moving" to (cursor.getInt(isMoving) == 1),
                "activity_confidence" to cursor.getInt(activityConfidence),
                "odometer" to cursor.getDouble(odometer)
            )
            cursor.getString(activityType)?.let { record["activity_type"] = it }
            cursor.getString(event)?.let { record["event"] = it }
            cursor.getString(extrasJson)?.let { record["extras_json"] = it }
            return record
        }
    }

    fun deleteLocations(ids: List<String>?) {
        if (ids.isNullOrEmpty()) return

        try {
            val db = writableDatabase
            val placeholders = ids.joinToString(",") { "?" }
            db.delete("locations", "id IN ($placeholders)", ids.toTypedArray())
            checkpoint(db)
        } catch (e: Exception) {
            android.util.Log.e("LocationStore", "Failed to delete locations: ${e.message}", e)
        }
    }

    private fun pruneByAge(maxDays: Int) {
        val cutoff = System.currentTimeMillis() - (maxDays * 24L * 60L * 60L * 1000L)
        writableDatabase.delete("locations", "timestamp < ?", arrayOf(cutoff.toString()))
    }

    private fun pruneByCount(maxRecords: Int) {
        writableDatabase.execSQL(
            """
            DELETE FROM locations WHERE id IN (
                SELECT id FROM locations ORDER BY timestamp DESC LIMIT -1 OFFSET ?
            )
            """.trimIndent(),
            arrayOf(maxRecords)
        )
    }

    private fun Any?.toDoubleOrZero(): Double = (this as? Number)?.toDouble() ?: 0.0

    /**
     * Bound the WAL file size after a write transaction. PASSIVE never blocks
     * readers and is a no-op if no work is needed; the DB stays durable either
     * way thanks to synchronous=FULL.
     */
    private fun checkpoint(db: SQLiteDatabase) {
        try {
            db.rawQuery("PRAGMA wal_checkpoint(PASSIVE)", null).use { it.moveToFirst() }
        } catch (e: Exception) {
            android.util.Log.w("LocationStore", "wal_checkpoint failed: ${e.message}")
        }
    }

    companion object {
        private const val MICROS_PER_MILLISECOND = 1000L
        private const val DB_NAME = "locus.db"
        private const val DB_VERSION = 3
    }
}
