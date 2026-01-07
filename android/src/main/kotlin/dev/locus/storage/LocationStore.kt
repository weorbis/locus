package dev.locus.storage

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.location.Location
import java.time.Instant
import java.util.UUID

class LocationStore(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

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
                odometer REAL
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS locations")
        onCreate(db)
    }

    fun insertLocation(
        location: Location,
        isMoving: Boolean,
        activityType: String?,
        activityConfidence: Int,
        event: String?,
        odometer: Double
    ) {
        try {
            writableDatabase.execSQL(
                """
                INSERT OR REPLACE INTO locations 
                (id, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_moving, activity_type, activity_confidence, event, odometer) 
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    UUID.randomUUID().toString(),
                    location.time,
                    location.latitude,
                    location.longitude,
                    location.accuracy,
                    location.speed,
                    location.bearing,
                    location.altitude,
                    if (isMoving) 1 else 0,
                    activityType,
                    activityConfidence,
                    event,
                    odometer
                )
            )
        } catch (e: Exception) {
            android.util.Log.e("LocationStore", "Failed to insert location: ${e.message}", e)
        }
    }

    fun clear() {
        try {
            writableDatabase.execSQL("DELETE FROM locations")
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

        writableDatabase.execSQL(
            """
            INSERT OR REPLACE INTO locations 
            (id, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_moving, activity_type, activity_confidence, event, odometer) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf(
                UUID.randomUUID().toString(),
                timestamp,
                latitude,
                longitude,
                accuracy,
                speed,
                heading,
                altitude,
                if (isMoving) 1 else 0,
                activityType,
                activityConfidence,
                event,
                odometer
            )
        )

            if (maxDays > 0) pruneByAge(maxDays)
            if (maxRecords > 0) pruneByCount(maxRecords)
        } catch (e: Exception) {
            // Log error but don't crash - graceful degradation
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
                while (cursor.moveToNext()) {
                    val record = mutableMapOf<String, Any>(
                        "id" to cursor.getString(cursor.getColumnIndexOrThrow("id")),
                        "timestamp" to cursor.getLong(cursor.getColumnIndexOrThrow("timestamp")),
                        "latitude" to cursor.getDouble(cursor.getColumnIndexOrThrow("latitude")),
                        "longitude" to cursor.getDouble(cursor.getColumnIndexOrThrow("longitude")),
                        "accuracy" to cursor.getDouble(cursor.getColumnIndexOrThrow("accuracy")),
                        "speed" to cursor.getDouble(cursor.getColumnIndexOrThrow("speed")),
                        "heading" to cursor.getDouble(cursor.getColumnIndexOrThrow("heading")),
                        "altitude" to cursor.getDouble(cursor.getColumnIndexOrThrow("altitude")),
                        "is_moving" to (cursor.getInt(cursor.getColumnIndexOrThrow("is_moving")) == 1),
                        "activity_confidence" to cursor.getInt(cursor.getColumnIndexOrThrow("activity_confidence")),
                        "odometer" to cursor.getDouble(cursor.getColumnIndexOrThrow("odometer"))
                    )
                    cursor.getString(cursor.getColumnIndexOrThrow("activity_type"))?.let { record["activity_type"] = it }
                    cursor.getString(cursor.getColumnIndexOrThrow("event"))?.let { record["event"] = it }
                    results.add(record)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("LocationStore", "Failed to read locations: ${e.message}", e)
        }
        return results
    }

    fun deleteLocations(ids: List<String>?) {
        if (ids.isNullOrEmpty()) return

        try {
            val placeholders = ids.joinToString(",") { "?" }
            writableDatabase.delete("locations", "id IN ($placeholders)", ids.toTypedArray())
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

    companion object {
        private const val DB_NAME = "locus.db"
        private const val DB_VERSION = 2
    }
}
