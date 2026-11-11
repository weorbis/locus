# Data protection

## Android

Locus always encrypts the location history, HTTP queue and diagnostic log databases (`locus.db`, `locus_queue.db`, `locus_logs.db`) with SQLCipher. No configuration or host-provided key is needed, and history filtering and paging still run in native SQL.

- **Key:** one random 32-byte key per installation, wrapped by an Android Keystore AES-GCM key (alias `dev.locus.database.v1`). Only the wrapped key is stored on disk.
- **Location:** the databases and the wrapped key live in `Context.noBackupFilesDir`, which Auto Backup and device transfer skip. Reinstalling or clearing app data removes the history, and a restore does not bring it back.
- **Migration:** on the first start after upgrading, existing plaintext databases are exported to encrypted files, checked (schema version, row counts, integrity), and only then deleted. The step runs once, off the main thread, under a file lock, and resumes if the process is killed. Location fixes that arrive while it runs are held in memory and written afterwards, so a process kill during this one-time step (or, for a few milliseconds, during a normal start) loses them. Keep free space for two copies of the databases during the upgrade.
- **Failure:** if the Keystore or the migration fails, existing files are left untouched and nothing falls back to plaintext or a new key. The app keeps running. Storage calls from Dart (`getLocations`, `query`, `enqueue`, `getQueue`, clears and the like) fail with `STORAGE_UNAVAILABLE` instead of returning success or empty data, an `error` event with the same code is emitted, and Locus retries on later access (at most every 30 seconds) and on the next start. Location fixes received meanwhile are held in memory (the newest 1,000) and saved once storage works again; a process kill in between loses them. If the key file is unreadable (for example torn by a kill while it was first written) and no encrypted database exists yet, it is discarded and a new key is created; once an encrypted database exists, Locus never replaces the key.
- **Size:** SQLCipher 4.20.0 adds 1,057,676 bytes (armeabi-v7a), 2,110,992 (arm64-v8a), 2,260,832 (x86) and 2,249,352 (x86_64) of native libraries before compression, plus shared Java code. These are library sizes, not measured APK deltas.

This protects copied database files. It does not protect against a compromised app process, and it does not cover host exports, network traffic or earlier backups. Downgrading to a version that reads only the old directory cannot read migrated data.

## iOS

Locus encrypts `Documents/locus_storage.sqlite` with SQLCipher 4.20.0 on iOS.
No Dart setting or host-supplied key is needed. The whole database is covered:
locations (including extras), geofences, sync queues, dead letters, logs, and
migration receipts. WAL pages are encrypted and temporary SQL data stays in memory.

- **Key:** a random 32-byte key stored as a Keychain item with
  `AfterFirstUnlockThisDeviceOnly`, so background tracking works after the first
  unlock following a reboot. The key never appears in SQLite, preferences, or logs.
- **Location:** `Documents/locus_storage.sqlite` (plus `-wal` and `-shm`), with
  `completeUntilFirstUserAuthentication` file protection and backup exclusion.
- **Migration:** an existing plaintext database is copied with `sqlcipher_export`
  in the background after launch, row counts and integrity are verified, then the
  file is replaced atomically. No plaintext copy is kept. Storage calls wait for
  it to finish. It needs free space for a second copy of the database.
- **Failure:** if the Keychain is unavailable (for example before first unlock
  after a reboot) or migration fails, nothing falls back to plaintext, existing
  files are left untouched, and Locus logs the cause. The app keeps running.
  Reads and writes from Dart (`getLocations`, `query`, `getLog`, geofence calls,
  `enqueue`, `getQueue`, `sync`, `syncQueue` and the like) fail with `STORAGE_UNAVAILABLE` instead of
  returning empty data, and stored geofences are not re-armed or edited until
  storage works. Locus retries as soon as iOS reports that protected data is
  available (this also works when the app was launched in the background) and on
  later access, at most every 30 seconds, and re-arms stored geofences when it
  succeeds. Location fixes received meanwhile are held in memory (the newest
  1,000) and written in order once storage works, after which their sync runs; a
  process kill in between loses them. Geofence enter and exit events received
  meanwhile are held too (the newest 100) and delivered in order at that point,
  and background refresh skips sync until storage works. If an encrypted database exists but its
  Keychain key is missing or unreadable, Locus never creates a replacement key,
  because it could not open that database; a new key is created only when no
  encrypted database exists.
- **Size:** about +1.5 MB for the framework and +0.72 MB for the zipped app.
  SQLite and SQLCipher symbols are prefixed, so host libraries such as sqflite
  keep using system SQLite. Hosts must retain SQLCipher's
  [BSD attribution](../../ios/locus/Sources/LocusSQLCipher/LICENSE.md).

Do not delete the Keychain item: the database cannot be recovered without its key,
and Locus reuses an existing valid key. Do not downgrade to a release that only
understands plaintext SQLite after migration.

Encryption protects files extracted from storage. It does not protect against a
compromised running app, secure HTTP transport, guarantee forensic erasure of the
old plaintext file from flash or old device backups, or establish regulatory
compliance. See the [vendor notes](../../ios/locus/Sources/LocusSQLCipher/README.md)
for source provenance and updates.
