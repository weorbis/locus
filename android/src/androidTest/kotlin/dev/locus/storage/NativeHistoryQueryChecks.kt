package dev.locus.storage

import android.content.ContentValues
import android.content.Context
import android.content.ContextWrapper
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import java.io.File
import java.util.UUID

/** Real Android SQLite checks; never opens a host application's database. */
internal class NativeHistoryQueryChecks(private val context: Context) {
    fun checks(): List<Pair<String, () -> Unit>> = listOf(
        "testHistoryFiltersBeforePagingInBothOrders" to ::verifyFilteredPaging,
        "testHistoryTimeEdgesRoundAtMicrosecondPrecision" to ::verifyTimeEdges,
        "testHistoryPagingAndEmptyRanges" to ::verifyPaging,
        "testHistoryNaNBoundsAndThresholds" to ::verifyNaN,
        "testHistoryInvalidCoordinateFallback" to ::verifyCoordinateFallback,
    )

    private fun verifyFilteredPaging() = withStore { store ->
        // These older excluded rows detect implementations that page before filtering.
        repeat(100) { index -> insert(store, "excluded-$index", index.toLong(), moving = false) }
        insert(store, "southwest", 200, latitude = 10.0, longitude = 20.0, accuracy = 10.0)
        insert(store, "tie-first", 210, accuracy = 15.0)
        insert(store, "tie-second", 210, accuracy = 15.0)
        insert(store, "northeast", 220, latitude = 11.0, longitude = 21.0, accuracy = 20.0)
        insert(store, "too-early", 199)
        insert(store, "too-late", 221)
        insert(store, "too-precise", 211, accuracy = 9.9)
        insert(store, "too-imprecise", 211, accuracy = 20.1)
        insert(store, "stationary", 211, moving = false)
        insert(store, "south", 211, latitude = 9.9)
        insert(store, "north", 211, latitude = 11.1)
        insert(store, "west", 211, longitude = 19.9)
        insert(store, "east", 211, longitude = 21.1)
        val query = mapOf(
            "from" to 200_000L, "to" to 220_000L,
            "minAccuracy" to 20.0, "maxAccuracy" to 10.0, "isMoving" to true,
            "bounds" to bounds(10.0, 20.0, 11.0, 21.0),
        )
        val countBefore = store.readLocations(0).size
        expectIds(store, query + mapOf("sortOrder" to "oldestFirst"), "southwest", "tie-first", "tie-second", "northeast")
        expectIds(store, query, "northeast", "tie-first", "tie-second", "southwest")
        expectIds(store, query + mapOf("sortOrder" to "oldestFirst", "offset" to 1, "limit" to 3), "tie-first", "tie-second", "northeast")
        expectIds(store, query + mapOf("offset" to 1, "limit" to 3), "tie-first", "tie-second", "southwest")
        expectIds(store, mapOf("isMoving" to false, "from" to 200_000L), "stationary")
        equal(countBefore, store.readLocations(0).size, "queries must preserve every stored row")
    }

    private fun verifyTimeEdges() = withStore { store ->
        for (time in listOf(-2L, -1L, 0L, 1L, 2L)) insert(store, "time-$time", time)
        expectIds(store, mapOf("from" to -999L, "to" to 999L), "time-0")
        expectIds(store, mapOf("from" to -1_999L, "to" to -1_001L))
        expectIds(store, mapOf("from" to -2_000L, "to" to -1_000L), "time--1", "time--2")
        expectIds(store, mapOf("from" to 1L, "to" to 1_999L), "time-1")
        expectIds(store, mapOf("from" to 1_001L, "to" to 2_000L), "time-2")
        expectIds(store, mapOf("from" to Long.MIN_VALUE, "to" to Long.MAX_VALUE), "time-2", "time-1", "time-0", "time--1", "time--2")
    }

    private fun verifyPaging() = withStore { store ->
        insert(store, "first", 1)
        insert(store, "second", 2)
        expectIds(store, mapOf("offset" to -20), "second", "first")
        expectIds(store, mapOf("offset" to 1), "first")
        expectIds(store, mapOf("offset" to Long.MAX_VALUE))
        for (limit in listOf(0L, -1L, Long.MIN_VALUE)) expectIds(store, mapOf("limit" to limit))
        expectIds(store, mapOf("from" to 3_000L, "to" to 1_000L))
        expectIds(store, mapOf("minAccuracy" to 10, "maxAccuracy" to 20))
        expectIds(store, mapOf("bounds" to bounds(11.0, 21.0, 10.0, 20.0)))
        equal(2, store.readLocations(0).size, "empty queries preserve rows")
    }

    private fun verifyNaN() = withStore { store ->
        insert(store, "accurate", 1, accuracy = 5.0)
        insert(store, "inaccurate", 2, accuracy = 50.0)
        expectIds(store, mapOf("minAccuracy" to Double.NaN, "maxAccuracy" to Double.NaN), "inaccurate", "accurate")
        expectIds(store, mapOf("minAccuracy" to Double.NaN, "maxAccuracy" to 10.0), "inaccurate")
        expectIds(store, mapOf("minAccuracy" to 10.0, "maxAccuracy" to Double.NaN), "accurate")
        for (edge in 0..3) {
            val coordinates = mutableListOf(10.0, 20.0, 11.0, 21.0)
            coordinates[edge] = Double.NaN
            expectIds(store, mapOf("bounds" to bounds(coordinates[0], coordinates[1], coordinates[2], coordinates[3])))
        }
    }

    private fun verifyCoordinateFallback() = withStore { store ->
        insert(store, "invalid-latitude", 1, latitude = 91.0, longitude = 20.0, accuracy = 50.0)
        insert(store, "invalid-longitude", 2, latitude = 10.0, longitude = -181.0, accuracy = 50.0)
        insert(store, "null-coordinates", 3, latitude = null, longitude = null, accuracy = null)
        insert(store, "valid", 4, latitude = 10.0, longitude = 20.0)
        expectIds(store, mapOf("bounds" to bounds(0.0, 0.0, 0.0, 0.0)), "null-coordinates", "invalid-longitude", "invalid-latitude")
        expectIds(store, mapOf("minAccuracy" to -1.0), "invalid-longitude", "invalid-latitude")
        expectIds(store, mapOf("maxAccuracy" to 0.0), "valid", "null-coordinates")
    }

    private fun requireTestContext() {
        check(context.packageName == "dev.locus.test") { "Native checks require the isolated library test package" }
    }

    private fun withStore(check: (LocationStore) -> Unit) {
        requireTestContext()
        val directory = File(context.cacheDir, "native-history-${UUID.randomUUID()}")
        check(directory.mkdir()) { "Cannot create isolated history fixture directory" }
        val isolated = object : ContextWrapper(context) {
            override fun getDatabasePath(name: String): File = File(directory, name)
            override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
                openOrCreateDatabase(name, mode, factory, null)

            override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?, errorHandler: DatabaseErrorHandler?): SQLiteDatabase =
                SQLiteDatabase.openOrCreateDatabase(getDatabasePath(name).path, factory, errorHandler)
        }
        val store = LocationStore(isolated)
        try {
            check(store)
        } finally {
            store.close()
            // Only this check's new scratch database is eligible for cleanup.
            directory.listFiles()?.filter { it.name.endsWith(".db") }?.forEach { database ->
                check(SQLiteDatabase.deleteDatabase(database)) { "Cannot remove history fixture database" }
            }
            check(directory.delete()) { "Cannot remove history fixture directory" }
        }
    }

    private fun insert(store: LocationStore, id: String, timestamp: Long, latitude: Double? = 10.5, longitude: Double? = 20.5, accuracy: Double? = 15.0, moving: Boolean = true) {
        val values = ContentValues().apply {
            put("id", id)
            put("timestamp", timestamp)
            put("latitude", latitude)
            put("longitude", longitude)
            put("accuracy", accuracy)
            put("is_moving", if (moving) 1 else 0)
        }
        store.writableDatabase.insertOrThrow("locations", null, values)
    }

    private fun expectIds(store: LocationStore, arguments: Map<String, Any>, vararg ids: String) {
        val result = store.queryLocations(StoredLocationQuery.fromArguments(arguments))
        equal(ids.toList(), result.map { it["id"] }, "history selection for $arguments")
    }

    private fun bounds(south: Double, west: Double, north: Double, east: Double): Map<String, Map<String, Double>> = mapOf(
        "southwest" to mapOf("latitude" to south, "longitude" to west),
        "northeast" to mapOf("latitude" to north, "longitude" to east),
    )

    private fun equal(expected: Any?, actual: Any?, label: String) {
        if (expected != actual) throw AssertionError("$label: expected <$expected>, actual <$actual>")
    }
}
