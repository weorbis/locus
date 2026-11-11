# Data protection

## Android

Locus always encrypts the location history, HTTP queue and diagnostic log databases (`locus.db`, `locus_queue.db`, `locus_logs.db`) with SQLCipher. No configuration or host-provided key is needed, and history filtering and paging still run in native SQL.

- **Key:** one random 32-byte key per installation, wrapped by an Android Keystore AES-GCM key (alias `dev.locus.database.v1`). Only the wrapped key is stored on disk.
- **Location:** the databases and the wrapped key live in `Context.noBackupFilesDir`, which Auto Backup and device transfer skip. Reinstalling or clearing app data removes the history, and a restore does not bring it back.
- **Migration:** on the first start after upgrading, existing plaintext databases are exported to encrypted files, checked (schema version, row counts, integrity), and only then deleted. The step runs once, off the main thread, under a file lock, and resumes if the process is killed. Location fixes that arrive while it runs are held in memory and written afterwards, so a process kill during this one-time step (or, for a few milliseconds, during a normal start) loses them. Keep free space for two copies of the databases during the upgrade.
- **Failure:** if the Keystore or the migration fails, existing files are left untouched and nothing falls back to plaintext or a new key. The app keeps running. Storage calls from Dart (`getLocations`, `query`, `enqueue`, `getQueue`, clears and the like) fail with `STORAGE_UNAVAILABLE` instead of returning success or empty data, an `error` event with the same code is emitted, and Locus retries on later access (at most every 30 seconds) and on the next start. Location fixes received meanwhile are held in memory (the newest 1,000) and saved once storage works again; a process kill in between loses them. If the key file is unreadable (for example torn by a kill while it was first written) and no encrypted database exists yet, it is discarded and a new key is created; once an encrypted database exists, Locus never replaces the key.
- **Size:** SQLCipher 4.20.0 adds 1,057,676 bytes (armeabi-v7a), 2,110,992 (arm64-v8a), 2,260,832 (x86) and 2,249,352 (x86_64) of native libraries before compression, plus shared Java code. These are library sizes, not measured APK deltas.

This protects copied database files. It does not protect against a compromised app process, and it does not cover host exports, network traffic or earlier backups. Downgrading to a version that reads only the old directory cannot read migrated data.
