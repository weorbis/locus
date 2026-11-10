# Data protection

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
  `enqueue`, `getQueue` and the like) fail with `STORAGE_UNAVAILABLE` instead of
  returning empty data, and stored geofences are not re-armed or edited until
  storage works. Locus retries as soon as iOS reports that protected data is
  available (this also works when the app was launched in the background) and on
  later access, at most every 30 seconds, and re-arms stored geofences when it
  succeeds. Location fixes received meanwhile are held in memory (the newest
  1,000) and written in order once storage works, after which their sync runs; a
  process kill in between loses them. If an encrypted database exists but its
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
