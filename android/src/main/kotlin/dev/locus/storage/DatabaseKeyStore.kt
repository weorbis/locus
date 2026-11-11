package dev.locus.storage

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Log
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal object DatabaseKeyStore {
    private const val TAG = "locus"
    private const val KEY_ALIAS = "dev.locus.database.v1"
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val KEY_BYTES = 32
    private const val BITS_PER_BYTE = 8
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128
    private const val ENVELOPE_VERSION = 1
    private const val KEY_FILE = "locus-database-key"

    // Called only while EncryptedStorage holds both the process and file locks.
    fun readOrCreate(directory: File, hasEncryptedDatabase: Boolean): ByteArray {
        val keyFile = File(directory, KEY_FILE)
        val envelope = AtomicFile(keyFile)
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        if (keyFile.exists() || File(keyFile.path + ".bak").exists()) {
            try {
                return read(envelope, keyStore)
            } catch (error: Exception) {
                // Never mint over existing encrypted data: without it the key protects nothing, so a
                // torn envelope (kill during the first write on API 26-30) is discarded and replaced.
                if (hasEncryptedDatabase) throw error
                Log.w(TAG, "Unreadable database key envelope and no encrypted database yet; minting a new key", error)
                envelope.delete()
            }
        }
        check(!hasEncryptedDatabase) { "Database key envelope is missing; existing databases are preserved" }
        val wrappingKey = (keyStore.getKey(KEY_ALIAS, null) as? SecretKey) ?: run {
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
            generator.init(
                KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(KEY_BYTES * BITS_PER_BYTE)
                    .setRandomizedEncryptionRequired(true)
                    .build()
            )
            generator.generateKey()
        }
        val key = ByteArray(KEY_BYTES).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance(TRANSFORMATION).apply {
            init(Cipher.ENCRYPT_MODE, wrappingKey)
            updateAAD(KEY_ALIAS.toByteArray(Charsets.UTF_8))
        }
        check(cipher.iv.size == IV_BYTES) { "Invalid database key IV" }
        val ciphertext = cipher.doFinal(key)
        val stream = envelope.startWrite()
        try {
            val output = DataOutputStream(stream)
            output.writeInt(ENVELOPE_VERSION)
            output.write(cipher.iv)
            output.write(ciphertext)
            output.flush()
            envelope.finishWrite(stream)
        } catch (error: Exception) {
            envelope.failWrite(stream)
            throw error
        }
        return key
    }

    private fun read(envelope: AtomicFile, keyStore: KeyStore): ByteArray {
        val wrappingKey = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
            ?: error("Database wrapping key is unavailable")
        return DataInputStream(envelope.openRead()).use { input ->
            check(input.readInt() == ENVELOPE_VERSION) { "Unsupported database key envelope" }
            val iv = ByteArray(IV_BYTES).also { input.readFully(it) }
            val ciphertext = ByteArray(KEY_BYTES + TAG_BITS / BITS_PER_BYTE).also { input.readFully(it) }
            check(input.read() == -1) { "Invalid database key envelope" }
            Cipher.getInstance(TRANSFORMATION).run {
                init(Cipher.DECRYPT_MODE, wrappingKey, GCMParameterSpec(TAG_BITS, iv))
                updateAAD(KEY_ALIAS.toByteArray(Charsets.UTF_8))
                doFinal(ciphertext).also { check(it.size == KEY_BYTES) }
            }
        }
    }
}
