package dev.locus.core

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.util.Log
import dev.locus.LocusPlugin
import dev.locus.storage.NativeHistoryQueryChecks

/** Runs the persisted-config parser contract against Android's real org.json. */
class ConfigSnapshotInstrumentation : Instrumentation() {

    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        val checks = listOf(
            "testProductionParserDecodesNestedSnapshot" to ::verifyNestedSnapshot,
            "testProductionParserClassifiesMalformedSnapshotAsCorrupt" to ::verifyMalformedSnapshot,
            "testConfigSnapshotIsEncryptedAndRestored" to ::verifyEncryptedPersistence,
            "testLegacyPlaintextSnapshotIsReadAndMigrated" to ::verifyLegacyMigration,
            "testReadyConfigPreservesPreexistingPrivacyGuard" to ::verifyPrivacyGuardMerge,
        ) + NativeHistoryQueryChecks(targetContext).checks()
        val failures = checks.mapIndexedNotNull { index, (name, check) ->
            reportCheckStarted(name, index + 1, checks.size)
            try {
                check()
                reportCheckFinished(name, index + 1, checks.size)
                null
            } catch (error: Throwable) {
                Log.e(TAG, "$name failed", error)
                reportCheckFailed(name, index + 1, checks.size, error)
                error
            }
        }

        val results = Bundle().apply {
            putString(
                RESULT_STREAM,
                if (failures.isEmpty()) {
                    "Config snapshot instrumentation passed\n"
                } else {
                    "Config snapshot instrumentation failed: ${failures.size} check(s) failed\n"
                },
            )
        }
        finish(if (failures.isEmpty()) Activity.RESULT_OK else Activity.RESULT_CANCELED, results)
    }

    private fun verifyNestedSnapshot() {
        val decoded = decodePersistedConfig(
            serialized = """
                {
                  "distanceFilter": 25,
                  "notification": {
                    "title": "Tracking",
                    "actions": ["PAUSE", "STOP"]
                  },
                  "extras": {
                    "enabled": true,
                    "nullable": null
                  }
                }
            """.trimIndent(),
            decoder = ::parseConfigSnapshot,
        )

        requireEqual(PersistedConfigStatus.VALID, decoded.status, "valid status")
        requireEqual(null, decoded.error, "valid error")
        requireEqual(25, decoded.values["distanceFilter"], "distanceFilter")

        val notification = decoded.values["notification"] as? Map<*, *>
            ?: throw AssertionError("notification must be a map")
        requireEqual("Tracking", notification["title"], "notification title")
        requireEqual(listOf("PAUSE", "STOP"), notification["actions"], "notification actions")

        val extras = decoded.values["extras"] as? Map<*, *>
            ?: throw AssertionError("extras must be a map")
        requireEqual(true, extras["enabled"], "extras enabled")
        if (extras.containsKey("nullable")) {
            throw AssertionError("JSON null values must be omitted")
        }
    }

    private fun verifyMalformedSnapshot() {
        val decoded = decodePersistedConfig(
            serialized = "not-json",
            decoder = ::parseConfigSnapshot,
        )

        requireEqual(PersistedConfigStatus.CORRUPT, decoded.status, "corrupt status")
        if (decoded.values.isNotEmpty()) {
            throw AssertionError("Corrupt snapshots must not expose partial values")
        }
        if (decoded.error == null) {
            throw AssertionError("Corrupt snapshots must retain their parser error")
        }
    }

    private fun verifyEncryptedPersistence() {
        withEmptyPreferences { preferences ->
            val config = mapOf<String, Any>(
                "distanceFilter" to 37.5,
                "url" to "https://api.example.test/locations",
                "headers" to mapOf("Authorization" to "Bearer instrumented-secret"),
                "params" to mapOf("tenant" to "instrumented-tenant"),
                "extras" to mapOf("tripId" to "instrumented-trip"),
            )
            val manager = ConfigManager(targetContext)
            if (!manager.applyConfig(config)) {
                throw AssertionError("ConfigManager must persist a valid configuration")
            }

            val stored = preferences.getString(ConfigManager.LAST_CONFIG_KEY, null)
                ?: throw AssertionError("Encrypted snapshot must be stored")
            if (!stored.startsWith(ConfigSnapshotEnvelope.PREFIX)) {
                throw AssertionError("Snapshot must use the versioned encrypted envelope")
            }
            listOf(
                "Authorization",
                "instrumented-secret",
                "instrumented-tenant",
                "instrumented-trip",
            ).forEach { plaintext ->
                if (stored.contains(plaintext)) {
                    throw AssertionError("Encrypted snapshot exposed plaintext: $plaintext")
                }
            }

            val restored = ConfigManager(targetContext)
            restored.restoreConfig(restored.buildConfigSnapshot())
            requireEqual(37.5f, restored.distanceFilter, "restored distanceFilter")
            requireEqual(
                "Bearer instrumented-secret",
                restored.httpHeaders["Authorization"],
                "restored authorization header",
            )
            requireEqual("instrumented-tenant", restored.httpParams["tenant"], "restored param")
            requireEqual("instrumented-trip", restored.httpExtras["tripId"], "restored extra")
        }
    }

    private fun verifyLegacyMigration() {
        withEmptyPreferences { preferences ->
            val legacy = """
                {
                  "distanceFilter": 42,
                  "headers": {"Authorization": "Bearer legacy-secret"},
                  "params": {"tenant": "legacy-tenant"},
                  "extras": {"tripId": "legacy-trip"}
                }
            """.trimIndent()
            if (!preferences.edit().putString(ConfigManager.LAST_CONFIG_KEY, legacy).commit()) {
                throw AssertionError("Legacy fixture must be persisted")
            }

            val manager = ConfigManager(targetContext)
            manager.restoreConfig(manager.buildConfigSnapshot())
            requireEqual(42f, manager.distanceFilter, "legacy distanceFilter")
            requireEqual(
                "Bearer legacy-secret",
                manager.httpHeaders["Authorization"],
                "legacy authorization header",
            )
            requireEqual("legacy-tenant", manager.httpParams["tenant"], "legacy param")
            requireEqual("legacy-trip", manager.httpExtras["tripId"], "legacy extra")

            val migrated = preferences.getString(ConfigManager.LAST_CONFIG_KEY, null)
                ?: throw AssertionError("Migrated snapshot must remain stored")
            if (!migrated.startsWith(ConfigSnapshotEnvelope.PREFIX)) {
                throw AssertionError("Legacy snapshot must migrate to the encrypted envelope")
            }
            if (migrated.contains("legacy-secret")) {
                throw AssertionError("Migrated snapshot must not expose its credential")
            }
        }
    }

    private fun verifyPrivacyGuardMerge() {
        withEmptyPreferences { preferences ->
            val manager = ConfigManager(targetContext)
            if (!manager.persistPrivacyMode(true)) {
                throw AssertionError("Privacy fixture must establish its native guard")
            }
            if (!manager.applyConfig(mapOf("distanceFilter" to 25))) {
                throw AssertionError("Ready config must persist with a native privacy guard")
            }

            requireEqual(true, manager.privacyModeEnabled, "runtime privacy guard")
            requireEqual(
                true,
                manager.buildConfigSnapshot()["privacyModeEnabled"],
                "persisted privacy guard",
            )
            requireEqual(
                true,
                preferences.getBoolean("bg_privacy_mode", false),
                "dedicated privacy receipt",
            )
        }
    }

    private fun withEmptyPreferences(check: (SharedPreferences) -> Unit) {
        val preferences = targetContext.getSharedPreferences(
            LocusPlugin.PREFS_NAME,
            Context.MODE_PRIVATE,
        )
        if (!preferences.edit().clear().commit()) {
            throw AssertionError("Test preferences must be clear before execution")
        }
        try {
            check(preferences)
        } finally {
            preferences.edit().clear().commit()
        }
    }

    private fun requireEqual(expected: Any?, actual: Any?, label: String) {
        if (expected != actual) {
            throw AssertionError("$label: expected <$expected>, actual <$actual>")
        }
    }

    private fun reportCheckStarted(name: String, current: Int, total: Int) {
        sendStatus(STATUS_START, testStatus(name, current, total))
    }

    private fun reportCheckFinished(name: String, current: Int, total: Int) {
        sendStatus(STATUS_OK, testStatus(name, current, total))
    }

    private fun reportCheckFailed(name: String, current: Int, total: Int, error: Throwable) {
        sendStatus(
            STATUS_FAILURE,
            testStatus(name, current, total).apply {
                putString(REPORT_STACK, error.stackTraceToString())
            },
        )
    }

    private fun testStatus(name: String, current: Int, total: Int): Bundle = Bundle().apply {
        putString(REPORT_ID, TAG)
        putString(REPORT_CLASS, ConfigSnapshotInstrumentation::class.java.name)
        putString(REPORT_TEST, name)
        putInt(REPORT_CURRENT, current)
        putInt(REPORT_TOTAL, total)
    }

    private companion object {
        const val TAG = "LocusConfigSnapshotTest"
        const val RESULT_STREAM = "stream"
        const val REPORT_ID = "id"
        const val REPORT_CLASS = "class"
        const val REPORT_TEST = "test"
        const val REPORT_CURRENT = "current"
        const val REPORT_TOTAL = "numtests"
        const val REPORT_STACK = "stack"
        const val STATUS_START = 1
        const val STATUS_OK = 0
        const val STATUS_FAILURE = -2
    }
}
