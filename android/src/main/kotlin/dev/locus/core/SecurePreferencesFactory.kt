package dev.locus.core

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Factory for creating secure SharedPreferences instances.
 * 
 * Uses EncryptedSharedPreferences for secure storage of sensitive data.
 * Falls back to standard SharedPreferences if encryption initialization fails
 * (e.g., on devices with corrupted keystores).
 */
object SecurePreferencesFactory {
    private const val TAG = "locus.SecurePrefs"
    private const val ENCRYPTED_PREFS_NAME = "dev.locus.encrypted_preferences"
    private const val FALLBACK_PREFS_NAME = "dev.locus.preferences"

    /**
     * Creates a SharedPreferences instance with encryption if available.
     * 
     * @param context Application context
     * @return SharedPreferences instance (encrypted if possible, standard otherwise)
     */
    fun create(context: Context): SharedPreferences {
        return try {
            createEncryptedPreferences(context)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to create encrypted preferences, using fallback: ${e.message}")
            createFallbackPreferences(context)
        }
    }

    /**
     * Creates EncryptedSharedPreferences using AES256-GCM encryption.
     */
    private fun createEncryptedPreferences(context: Context): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        return EncryptedSharedPreferences.create(
            context,
            ENCRYPTED_PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    /**
     * Creates standard SharedPreferences as a fallback.
     */
    private fun createFallbackPreferences(context: Context): SharedPreferences {
        return context.getSharedPreferences(FALLBACK_PREFS_NAME, Context.MODE_PRIVATE)
    }

    /**
     * Migrates existing preferences from unencrypted to encrypted storage.
     * Call this once during app initialization to transfer any existing data.
     * 
     * @param context Application context
     * @param keysToMigrate List of preference keys to migrate
     * @return true if migration was successful or not needed
     */
    fun migrateToEncrypted(context: Context, keysToMigrate: List<String>): Boolean {
        val oldPrefs = context.getSharedPreferences(FALLBACK_PREFS_NAME, Context.MODE_PRIVATE)
        
        // Check if there's anything to migrate
        val hasDataToMigrate = keysToMigrate.any { oldPrefs.contains(it) }
        if (!hasDataToMigrate) {
            return true
        }

        return try {
            val newPrefs = createEncryptedPreferences(context)
            val editor = newPrefs.edit()

            keysToMigrate.forEach { key ->
                when (val value = oldPrefs.all[key]) {
                    is Long -> editor.putLong(key, value)
                    is Int -> editor.putInt(key, value)
                    is Boolean -> editor.putBoolean(key, value)
                    is String -> editor.putString(key, value)
                    is Float -> editor.putFloat(key, value)
                    is Set<*> -> {
                        @Suppress("UNCHECKED_CAST")
                        editor.putStringSet(key, value as Set<String>)
                    }
                }
            }

            editor.apply()

            // Clear old preferences after successful migration
            oldPrefs.edit().apply {
                keysToMigrate.forEach { remove(it) }
                apply()
            }

            Log.d(TAG, "Successfully migrated ${keysToMigrate.size} preference keys to encrypted storage")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to migrate preferences: ${e.message}")
            false
        }
    }
}
