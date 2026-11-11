package dev.locus.storage

import android.content.Context
import android.content.ContextWrapper
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import android.util.Log
import net.zetetic.database.DatabaseErrorHandler
import net.zetetic.database.sqlcipher.SQLiteDatabase
import net.zetetic.database.sqlcipher.SQLiteOpenHelper
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask

internal class EncryptedDatabaseContext(context: Context, val password: ByteArray) : ContextWrapper(context) {
    override fun getDatabasePath(name: String): File = File(noBackupFilesDir, name)
}

/**
 * Thrown when the encrypted stores cannot be used right now: still preparing on the main thread, or preparation failed.
 * Store reads, inserts and clears let it propagate so callers never report success or empty data for it;
 * only sync bookkeeping (deleting sent rows, retry counters) stays best-effort.
 */
internal class StorageUnavailableException(message: String, cause: Throwable? = null) : IllegalStateException(message, cause)

/** Builds a SQLCipher helper on first use, so constructing a store never touches the key or the disk. */
internal class LazyHelper<T : SQLiteOpenHelper>(
    private val context: Context,
    private val create: (EncryptedDatabaseContext) -> T,
) {
    @Volatile
    private var helper: T? = null

    fun get(): T = helper ?: run {
        // Opened outside the lock: worker threads may wait for preparation, the main thread never does.
        val opened = EncryptedStorage.open(context)
        synchronized(this) { helper ?: create(opened).also { helper = it } }
    }

    @Synchronized
    fun close() {
        helper?.close()
        helper = null
    }
}

/**
 * Prepares the encrypted databases (SQLCipher load, Keystore key unwrap, one-time plaintext migration).
 *
 * Preparation runs at most once per process and directory, on its own thread. A failed attempt is kept
 * (files stay untouched, nothing falls back to plaintext) and retried on a later access once
 * [RETRY_AFTER_FAILURE_MS] has passed, or on the next process start.
 * The main thread never waits: [open] throws there while preparation is running, so main-thread
 * entry points use [runWhenReady], which queues the work and replays it in order on the main thread,
 * one queued item per main-thread turn. Queued work lives in memory only: a process kill during
 * preparation (normally milliseconds, longer while the one-time plaintext migration runs) loses it.
 */
internal object EncryptedStorage {
    const val MINIMUM_SUPPORTED_VERSION = 0
    private const val TAG = "locus"
    private const val LOCK_FILE = "locus-database.lock"
    private const val MIGRATING_SUFFIX = ".migrating"
    private const val RETRY_AFTER_FAILURE_MS = 30_000L
    private const val NOT_FAILED = -1L
    private val DATABASE_NAMES = listOf("locus.db", "locus_queue.db", "locus_logs.db")
    private val SIDECAR_SUFFIXES = listOf("-wal", "-shm", "-journal")
    private val executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "locus-storage-prepare").apply { isDaemon = true }
    }
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private val attempts = mutableMapOf<String, Attempt>()
    private val pending = ArrayDeque<() -> Unit>()
    private var libraryLoaded = false

    val errorHandler = DatabaseErrorHandler { _, error -> throw error }

    /** Called on the main thread after each failed preparation attempt so tracking can report it. */
    @Volatile
    var failureListener: ((Throwable) -> Unit)? = null

    /** Called on the main thread after each successful preparation so held writes can be flushed. */
    @Volatile
    var readyListener: (() -> Unit)? = null

    private class Attempt(context: Context) : FutureTask<ByteArray>(Callable { prepare(context) }) {
        @Volatile
        var failedAtElapsedMs = NOT_FAILED

        fun isRetryable(): Boolean = failedAtElapsedMs != NOT_FAILED &&
            SystemClock.elapsedRealtime() - failedAtElapsedMs >= RETRY_AFTER_FAILURE_MS

        override fun done() {
            val failure = try {
                get()
                null
            } catch (error: ExecutionException) {
                error.cause ?: error
            }
            if (failure != null) {
                failedAtElapsedMs = SystemClock.elapsedRealtime()
                // The encrypted log store is unavailable during bootstrap. Use the SDK's Logcat tag.
                Log.e(TAG, "Encrypted storage initialization failed; files preserved, retry later", failure)
                mainHandler.post { failureListener?.invoke(failure) }
            } else {
                mainHandler.post { readyListener?.invoke() }
            }
            mainHandler.post(::drainNext)
        }
    }

    /** Starts preparation if it has not started (or a failed attempt may be retried). Never blocks. */
    fun start(context: Context) {
        attemptFor(context)
    }

    /**
     * Returns the database context once preparation succeeded. Waits on worker threads; on the main
     * thread it throws instead of waiting while preparation is still running.
     */
    fun open(context: Context): EncryptedDatabaseContext {
        val attempt = attemptFor(context)
        if (!attempt.isDone && Looper.myLooper() == Looper.getMainLooper()) {
            throw StorageUnavailableException("Encrypted storage is still being prepared")
        }
        try {
            return EncryptedDatabaseContext(context, attempt.get().copyOf())
        } catch (error: ExecutionException) {
            throw StorageUnavailableException("Locus encrypted storage is unavailable", error.cause ?: error)
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            throw StorageUnavailableException("Interrupted while preparing encrypted storage", error)
        }
    }

    /**
     * Runs [block] now if storage is prepared and nothing is queued, otherwise queues it and replays
     * the queue in order on the main thread once preparation finishes (successfully or not).
     * Store access that throws [StorageUnavailableException] is logged and dropped; callers that must
     * report it (method calls) or keep their data (location writes) catch it inside [block].
     */
    fun runWhenReady(context: Context, block: () -> Unit) {
        val attempt = attemptFor(context)
        val runNow = synchronized(pending) {
            if (attempt.isDone && pending.isEmpty()) {
                true
            } else {
                pending.addLast(block)
                false
            }
        }
        if (runNow) invoke(block)
    }

    /** Replays one queued item and posts the next, so a long backlog never holds the main thread in one turn. */
    private fun drainNext() {
        val next = synchronized(pending) { pending.removeFirstOrNull() } ?: return
        try {
            invoke(next)
        } catch (error: RuntimeException) {
            // Nothing may escape to the looper; one failing item must not strand the rest of the queue.
            Log.e(TAG, "Queued storage operation failed", error)
        }
        if (synchronized(pending) { pending.isNotEmpty() }) mainHandler.post(::drainNext)
    }

    private fun invoke(block: () -> Unit) {
        try {
            block()
        } catch (error: StorageUnavailableException) {
            Log.w(TAG, "Storage operation dropped: ${error.message} (${error.cause?.message})")
        }
    }

    private fun attemptFor(context: Context): Attempt = synchronized(attempts) {
        val identity = context.noBackupFilesDir.canonicalPath
        attempts[identity]?.takeUnless { it.isRetryable() } ?: Attempt(context).also {
            attempts[identity] = it
            executor.execute(it)
        }
    }

    private fun prepare(context: Context): ByteArray {
        val directory = context.noBackupFilesDir
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create encrypted database directory" }
        if (!libraryLoaded) {
            System.loadLibrary("sqlcipher")
            libraryLoaded = true
        }
        return RandomAccessFile(File(directory, LOCK_FILE), "rw").use { lockFile ->
            lockFile.channel.lock().use {
                val key = DatabaseKeyStore.readOrCreate(directory, DATABASE_NAMES.any { File(directory, it).exists() })
                val rawKey = "x'${key.joinToString("") { "%02x".format(it) }}'"
                key.fill(0)
                val encodedKey = rawKey.toByteArray(Charsets.UTF_8)
                for (name in DATABASE_NAMES) {
                    migrate(context.getDatabasePath(name), File(directory, name), encodedKey, rawKey)
                }
                encodedKey
            }
        }
    }

    private fun migrate(source: File, destination: File, password: ByteArray, rawKey: String) {
        val staging = File(destination.path + MIGRATING_SUFFIX)
        if (!source.exists()) {
            // A previous startup may have stopped after removing the verified source's main file.
            if (destination.exists()) removeSidecars(source)
            removeDatabaseFiles(staging)
            return
        }
        // CREATE_IF_NECESSARY is also what lets ATTACH create the staging file: attached files inherit the open flags.
        open(source, byteArrayOf(), SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY).use { plaintext ->
            plaintext.rawQuery("PRAGMA wal_checkpoint(TRUNCATE)", null).use { cursor ->
                check(cursor.moveToFirst() && cursor.getInt(0) == 0) { "Plaintext database is busy" }
            }
            if (!destination.exists()) {
                removeDatabaseFiles(staging)
                export(plaintext, staging, rawKey)
                open(staging, password, SQLiteDatabase.OPEN_READONLY).use { encrypted -> verify(plaintext, encrypted) }
                check(staging.renameTo(destination)) { "Cannot promote verified encrypted database" }
            } else {
                // Resume after promotion if the process stopped before plaintext cleanup.
                open(destination, password, SQLiteDatabase.OPEN_READONLY).use { encrypted -> verify(plaintext, encrypted) }
            }
        }
        syncDirectory(destination.parentFile ?: error("Missing encrypted database directory"))
        removeDatabaseFiles(source)
        syncDirectory(source.parentFile ?: error("Missing plaintext database directory"))
        Log.i(TAG, "Migrated ${source.name} to encrypted storage")
    }

    private fun export(plaintext: SQLiteDatabase, staging: File, rawKey: String) {
        plaintext.execSQL("ATTACH DATABASE ? AS encrypted KEY ?", arrayOf(staging.path, rawKey))
        try {
            plaintext.execSQL("PRAGMA encrypted.synchronous=FULL")
            plaintext.beginTransaction()
            try {
                plaintext.rawQuery("SELECT sqlcipher_export('encrypted')", null).use { it.moveToFirst() }
                plaintext.execSQL("PRAGMA encrypted.user_version=${plaintext.version}")
                plaintext.setTransactionSuccessful()
            } finally {
                plaintext.endTransaction()
            }
        } finally {
            plaintext.execSQL("DETACH DATABASE encrypted")
        }
    }

    private fun verify(plaintext: SQLiteDatabase, encrypted: SQLiteDatabase) {
        check(plaintext.version == encrypted.version) { "Database migration version mismatch" }
        val sourceCounts = rowCounts(plaintext)
        check(sourceCounts == rowCounts(encrypted)) { "Database migration row count mismatch" }
        encrypted.rawQuery("PRAGMA integrity_check", null).use { cursor ->
            check(cursor.moveToFirst() && cursor.getString(0) == "ok") { "Encrypted database integrity check failed" }
        }
        encrypted.rawQuery("PRAGMA cipher_integrity_check", null).use { cursor ->
            check(!cursor.moveToFirst()) { "Encrypted database authentication check failed" }
        }
    }

    private fun rowCounts(database: SQLiteDatabase): Map<String, Long> {
        val tables = mutableListOf<String>()
        database.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'", null).use { cursor ->
            while (cursor.moveToNext()) tables.add(cursor.getString(0))
        }
        return tables.associateWith { table ->
            val identifier = table.replace("\"", "\"\"")
            database.rawQuery("SELECT COUNT(*) FROM \"$identifier\"", null).use { cursor ->
                check(cursor.moveToFirst()) { "Cannot count database rows" }
                cursor.getLong(0)
            }
        }
    }

    private fun open(file: File, password: ByteArray, flags: Int): SQLiteDatabase =
        SQLiteDatabase.openDatabase(file.path, password, null, flags, errorHandler, null)

    private fun removeDatabaseFiles(file: File) {
        removeSidecars(file)
        check(!file.exists() || file.delete()) { "Cannot remove ${file.name}" }
    }

    private fun removeSidecars(file: File) {
        for (suffix in SIDECAR_SUFFIXES) {
            val sidecar = File(file.path + suffix)
            check(!sidecar.exists() || sidecar.delete()) { "Cannot remove database sidecar ${sidecar.name}" }
        }
    }

    private fun syncDirectory(directory: File) {
        val descriptor = Os.open(directory.path, OsConstants.O_RDONLY, 0)
        try {
            Os.fsync(descriptor)
        } finally {
            Os.close(descriptor)
        }
    }
}
