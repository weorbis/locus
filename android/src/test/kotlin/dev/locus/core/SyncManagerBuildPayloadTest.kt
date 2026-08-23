package dev.locus.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncManagerBuildPayloadTest {

    @Test
    fun `nested record with coords map is passed through unchanged`() {
        val nested = mapOf<String, Any>(
            "uuid" to "existing-uuid",
            "timestamp" to "2026-08-18T12:00:00Z",
            "coords" to mapOf(
                "latitude" to 1.23,
                "longitude" to 4.56,
                "accuracy" to 5.0,
            ),
            "activity" to mapOf("type" to "still", "confidence" to 90),
        )

        val payload = SyncManager.buildPayloadFromRecord(nested)

        assertSame(nested, payload)
        assertEquals("existing-uuid", payload["uuid"])
        assertEquals(nested["coords"], payload["coords"])
    }

    @Test
    fun `flat record with top-level coordinates is normalized into a coords map`() {
        val flat = mapOf<String, Any>(
            "id" to "flat-uuid",
            "timestamp" to 1_700_000_000_000L,
            "latitude" to 51.5,
            "longitude" to -0.12,
            "accuracy" to 10.0,
            "speed" to 2.5,
            "heading" to 90.0,
            "altitude" to 15.0,
        )

        val payload = SyncManager.buildPayloadFromRecord(flat)

        assertEquals("flat-uuid", payload["uuid"])
        assertTrue(payload["coords"] is Map<*, *>)
        val coords = payload["coords"] as Map<*, *>
        assertEquals(51.5, coords["latitude"])
        assertEquals(-0.12, coords["longitude"])
        assertEquals(10.0, coords["accuracy"])
        assertEquals(2.5, coords["speed"])
        assertEquals(90.0, coords["heading"])
        assertEquals(15.0, coords["altitude"])
        assertTrue(payload.containsKey("timestamp"))
        assertEquals(false, payload.containsKey("latitude"))
    }

    @Test
    fun `flat record missing required coordinates is dropped`() {
        val incomplete = mapOf<String, Any>(
            "timestamp" to 1_700_000_000_000L,
            "latitude" to 51.5,
        )

        val payload = SyncManager.buildPayloadFromRecord(incomplete)

        assertEquals(emptyMap<String, Any>(), payload)
    }

    @Test
    fun `null record returns an empty payload`() {
        val payload = SyncManager.buildPayloadFromRecord(null)

        assertEquals(emptyMap<String, Any>(), payload)
    }
}
