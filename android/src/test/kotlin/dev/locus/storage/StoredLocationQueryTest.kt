package dev.locus.storage

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class StoredLocationQueryTest {
    @Test
    fun `empty query defaults to unlimited newest first without offset`() {
        val query = StoredLocationQuery.fromArguments(emptyMap<String, Any>())
        assertNull(query.from)
        assertNull(query.to)
        assertNull(query.limit)
        assertNull(query.bounds)
        assertNull(query.isMoving)
        assertEquals(0L, query.offset)
        assertFalse(query.oldestFirst)
    }

    @Test
    fun `timestamps and paging accept both channel integer widths without truncation`() {
        val query = StoredLocationQuery.fromArguments(
            mapOf("from" to -1, "to" to Long.MAX_VALUE, "limit" to 3, "offset" to 2L),
        )
        assertEquals(-1L, query.from)
        assertEquals(Long.MAX_VALUE, query.to)
        assertEquals(3L, query.limit)
        assertEquals(2L, query.offset)
    }

    @Test
    fun `integral fields reject floating numbers strings and booleans`() {
        for (key in listOf("from", "to", "limit", "offset")) {
            for (value in listOf(1.0, 1.5, "1", true)) {
                val error = assertThrows(IllegalArgumentException::class.java) {
                    StoredLocationQuery.fromArguments(mapOf(key to value))
                }
                assertEquals("Expected integral $key", error.message)
            }
        }
    }

    @Test
    fun `negative offset clamps to zero while nonpositive limits remain empty requests`() {
        for (limit in listOf(0L, -1L, Long.MIN_VALUE)) {
            val query = StoredLocationQuery.fromArguments(mapOf("offset" to -3, "limit" to limit))
            assertEquals(0L, query.offset)
            assertEquals(limit, query.limit)
        }
    }

    @Test
    fun `motion requires a boolean and sort requires a supported value`() {
        for (moving in listOf(true, false)) {
            assertEquals(moving, StoredLocationQuery.fromArguments(mapOf("isMoving" to moving)).isMoving)
        }
        for (invalid in listOf(0, "true", "false")) {
            assertThrows(IllegalArgumentException::class.java) {
                StoredLocationQuery.fromArguments(mapOf("isMoving" to invalid))
            }
        }
        assertTrue(StoredLocationQuery.fromArguments(mapOf("sortOrder" to "oldestFirst")).oldestFirst)
        assertFalse(StoredLocationQuery.fromArguments(mapOf("sortOrder" to "newestFirst")).oldestFirst)
        for (invalid in listOf("ascending", "", true, 1)) {
            assertThrows(IllegalArgumentException::class.java) {
                StoredLocationQuery.fromArguments(mapOf("sortOrder" to invalid))
            }
        }
    }

    @Test
    fun `bounds require complete numeric corners`() {
        val southwest = mapOf("latitude" to 10, "longitude" to 20.5)
        val northeast = mapOf("latitude" to 11.5, "longitude" to 21)
        val query = StoredLocationQuery.fromArguments(
            mapOf("bounds" to mapOf("southwest" to southwest, "northeast" to northeast)),
        )
        assertEquals(StoredLocationQuery.Bounds(10.0, 20.5, 11.5, 21.0), query.bounds)
        for (bounds in listOf(
            "rectangle",
            emptyMap<String, Any>(),
            mapOf("southwest" to southwest),
            mapOf("southwest" to "corner", "northeast" to northeast),
            mapOf("southwest" to mapOf("latitude" to 10), "northeast" to northeast),
            mapOf("southwest" to mapOf("latitude" to true, "longitude" to 20), "northeast" to northeast),
        )) {
            assertThrows(IllegalArgumentException::class.java) {
                StoredLocationQuery.fromArguments(mapOf("bounds" to bounds))
            }
        }
    }

    @Test
    fun `accuracy thresholds require numbers and preserve NaN for query semantics`() {
        val query = StoredLocationQuery.fromArguments(mapOf("minAccuracy" to 20, "maxAccuracy" to Double.NaN))
        assertEquals(20.0, query.minAccuracy)
        assertTrue(query.maxAccuracy?.isNaN() == true)
        for (key in listOf("minAccuracy", "maxAccuracy")) {
            for (invalid in listOf("20", false)) {
                assertThrows(IllegalArgumentException::class.java) {
                    StoredLocationQuery.fromArguments(mapOf(key to invalid))
                }
            }
        }
    }

    @Test
    fun `nonmap channel arguments are rejected`() {
        for (arguments in listOf(null, "query", 1, emptyList<String>())) {
            assertThrows(IllegalArgumentException::class.java) {
                StoredLocationQuery.fromArguments(arguments)
            }
        }
    }
}
