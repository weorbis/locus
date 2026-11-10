import Foundation
#if canImport(LocusSQLCipher)
import LocusSQLCipher
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Thrown when the encrypted database could not be prepared (for example the
/// Keychain is locked before first unlock) and storage cannot serve the call.
struct StorageUnavailableError: LocalizedError {
    let reason: String

    var errorDescription: String? { "Encrypted storage is unavailable: \(reason)" }
}

/// SQLite-based storage for locations, geofences, and queue items.
/// Replaces UserDefaults to support larger datasets and better performance.
class SQLiteStorage {

    /// SQLITE_TRANSIENT equivalent: tells SQLite to copy the string data immediately.
    /// Prevents use-after-free when Swift ARC deallocates the string before locus_sqlite3_step.
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: locus_sqlite3_destructor_type.self)

    private var db: OpaquePointer?
    private var encryptedDatabase: EncryptedSQLiteDatabase?
    private static let dbName = "locus_storage.sqlite"
    private static let busyTimeoutMilliseconds: Int32 = 5_000
    private let databaseURL: URL?
    private let userDefaults: UserDefaults
    private let keyProvider: () throws -> Data
    private let queue = DispatchQueue(label: "dev.locus.sqlite", qos: .utility)
    private let queryQueue = DispatchQueue(label: "dev.locus.sqlite.query", qos: .utility)
    /// Only used on `queryQueue`.
    private var readDb: OpaquePointer?
    private var readSupportsJSON = false

    /// Minimum time between automatic preparation retries triggered by access.
    /// The protected-data notification retries immediately, ignoring this.
    static let minimumPreparationRetryInterval: TimeInterval = 30
    /// Most location fixes held in memory while storage is unavailable; the
    /// oldest is dropped beyond this. Matches the Android limit.
    static let maximumHeldLocations = 1_000
    /// Insert attempts a held fix gets while the database is open before it is
    /// dropped, so one unwritable fix cannot block every fix behind it.
    static let maximumHeldWriteAttempts = 3

    private struct HeldLocation {
        let payload: [String: Any]
        let completion: (() -> Void)?
        var failedWrites = 0
    }

    /// Only used on `queue`.
    private var heldLocations: [HeldLocation] = []
    /// Only used on `queue`. System uptime of the last preparation attempt.
    private var lastPreparationAttempt: TimeInterval?
    /// Only used on `queue`. Why the last preparation attempt failed.
    private var preparationFailure = "storage has not been prepared"
    /// Only used on `queue`. Retention limits from the latest prune requested
    /// while storage was unavailable; applied after held fixes are written.
    private var pendingPrune: (maxDays: Int, maxRecords: Int)?
    /// Only used on `queue`. Called on the main queue after a retry succeeds.
    private var recoveryHandler: (() -> Void)?
    private var protectedDataObserver: NSObjectProtocol?

    init(
        databaseURL: URL? = nil,
        userDefaults: UserDefaults = .standard,
        keyProvider: (() throws -> Data)? = nil
    ) {
        let resolvedURL = databaseURL ?? Self.defaultDatabaseURL()
        self.databaseURL = resolvedURL
        self.userDefaults = userDefaults
        // A key may only be created while no encrypted database exists; an
        // encrypted database whose key is gone must never get a replacement.
        self.keyProvider = keyProvider ?? {
            let encryptedDatabaseExists = resolvedURL.map(EncryptedSQLiteDatabase.containsEncryptedDatabase(at:)) ?? false
            return try SecureStorage.shared.databaseKey(mayCreate: !encryptedDatabaseExists)
        }
        // Registered before the first attempt so an unlock between a failed
        // attempt and a later registration cannot be missed.
        observeProtectedData()
        // Key retrieval and the plaintext-to-encrypted migration can take long
        // on a large history, so they must not block plugin registration (the
        // app's main thread). Every other operation is dispatched to or
        // synchronized with `queue`, which is serial, so each one runs after this
        // block. `queryLocations` hops through `queue` before `queryQueue`, so the
        // read connection can only be opened after preparation finished.
        queue.async { [self] in
            prepareOnQueue()
        }
    }

    /// Registers `handler` to run on the main queue after storage becomes
    /// available on a retry, so callers can redo work they skipped meanwhile.
    func setRecoveryHandler(_ handler: @escaping () -> Void) {
        queue.async { [self] in
            recoveryHandler = handler
        }
    }

    private func observeProtectedData() {
        #if canImport(UIKit)
        // Keychain items readable only after first unlock fail with
        // errSecInteractionNotAllowed until then. The notification is also
        // delivered to a process launched in the background.
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { [weak self] in
                self?.retryPreparationOnQueue()
            }
        }
        #endif
    }

    /// True when the database is open; retries preparation first if one is due.
    var isAvailable: Bool {
        queue.sync {
            retryPreparationIfDueOnQueue()
            return db != nil
        }
    }

    /// Throws `StorageUnavailableError` unless the database is open. Once it
    /// returns normally the database stays open for the life of this object.
    func requireAvailable() throws {
        try queue.sync {
            retryPreparationIfDueOnQueue()
            guard db != nil else { throw StorageUnavailableError(reason: preparationFailure) }
        }
    }

    /// Caller must already hold `queue`. Runs `prepareOnQueue` unless the
    /// database is open or an attempt ran less than the minimum interval ago.
    private func retryPreparationIfDueOnQueue() {
        guard db == nil else { return }
        if let lastPreparationAttempt,
           ProcessInfo.processInfo.systemUptime - lastPreparationAttempt < Self.minimumPreparationRetryInterval {
            return
        }
        retryPreparationOnQueue()
    }

    /// Caller must already hold `queue`.
    private func retryPreparationOnQueue() {
        guard db == nil else { return }
        NSLog("[locus.SQLiteStorage] Retrying storage preparation")
        prepareOnQueue()
        guard db != nil, let recoveryHandler else { return }
        DispatchQueue.main.async(execute: recoveryHandler)
    }

    /// Opens (and if needed migrates) the database, creates tables and imports
    /// legacy UserDefaults rows, then writes any location fixes held while
    /// storage was unavailable. Runs as the first block on `queue` and again
    /// for each retry until it succeeds. Caller must already hold `queue`.
    private func prepareOnQueue() {
        lastPreparationAttempt = ProcessInfo.processInfo.systemUptime
        openDatabase()
        guard db != nil else { return }
        createTables()
        migrateFromUserDefaults()
        flushHeldLocationsOnQueue()
    }

    deinit {
        if let protectedDataObserver {
            NotificationCenter.default.removeObserver(protectedDataObserver)
        }
        // Every user of the connections holds `self`, so none is running now.
        for connection in [db, readDb] {
            guard let connection else { continue }
            let closeResult = locus_sqlite3_close(connection)
            if closeResult != LOCUS_SQLITE_OK {
                NSLog("[locus.SQLiteStorage] Database close failed: %d", closeResult)
            }
        }
    }
    
    // MARK: - Database Setup
    
    private func openDatabase() {
        guard let databaseURL else {
            NSLog("[locus.SQLiteStorage] Documents database directory is unavailable")
            preparationFailure = "the Documents directory is unavailable"
            db = nil
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("[locus.SQLiteStorage] Database directory creation failed: %@", error.localizedDescription)
            preparationFailure = error.localizedDescription
            db = nil
            return
        }

        do {
            let encrypted = try EncryptedSQLiteDatabase(url: databaseURL, key: keyProvider())
            db = try encrypted.open()
            encryptedDatabase = encrypted
        } catch {
            NSLog("[locus.SQLiteStorage] Encrypted storage unavailable; existing files are untouched and preparation will be retried: %@", error.localizedDescription)
            preparationFailure = error.localizedDescription
            db = nil
            return
        }
        // Durability: WAL keeps the journal independent of the main DB, and
        // synchronous=FULL fsyncs both files on commit. Together they survive
        // process kills between commit and checkpoint without data loss.
        locus_sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        locus_sqlite3_exec(db, "PRAGMA synchronous=FULL;", nil, nil, nil)
        // Wait up to 5s on contention rather than failing fast with LOCUS_SQLITE_BUSY.
        locus_sqlite3_busy_timeout(db, Self.busyTimeoutMilliseconds)
        protectDatabaseFiles()
    }

    private static func defaultDatabaseURL(fileManager: FileManager = .default) -> URL? {
        // Every released Locus version stores this database in Documents. Keep
        // that path canonical for both existing and new installations so an app
        // upgrade or downgrade can never split live tracking data across two
        // databases. File protection and backup exclusion are applied below.
        // TODO(locus-3.0): move to Application Support only with a transactional,
        // crash-resumable migration protocol understood by every supported version.
        databaseURL(
            documentsDirectory: fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        )
    }

    static func databaseURL(
        documentsDirectory: URL?
    ) -> URL? {
        documentsDirectory?.appendingPathComponent(dbName)
    }

    private func protectDatabaseFiles() {
        #if os(iOS)
        guard let databaseURL else { return }
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: url.path
                )
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var mutableURL = url
                try mutableURL.setResourceValues(values)
            } catch {
                NSLog("[locus.SQLiteStorage] File protection failed: %@", error.localizedDescription)
            }
        }
        #endif
    }

    /// Bound the WAL file size after a write. PASSIVE never blocks readers and
    /// is a no-op when no work is needed; durability is provided by
    /// synchronous=FULL on the original commit.
    /// Caller must already hold `queue`.
    private func walCheckpointOnQueue() {
        guard let db = self.db else { return }
        locus_sqlite3_exec(db, "PRAGMA wal_checkpoint(PASSIVE);", nil, nil, nil)
    }

    /// Steps a write statement (INSERT/UPDATE/DELETE/PRAGMA): retries on
    /// LOCUS_SQLITE_BUSY, expects LOCUS_SQLITE_DONE, and logs `locus_sqlite3_errmsg` for any
    /// other result so DB failures aren't silent. Returns true on success.
    /// Caller must already hold `queue`.
    @discardableResult
    private func stepChecked(_ statement: OpaquePointer?, op: String) -> Bool {
        var rc = locus_sqlite3_step(statement)
        var attempts = 0
        while rc == LOCUS_SQLITE_BUSY && attempts < 5 {
            attempts += 1
            rc = locus_sqlite3_step(statement)
        }
        if rc != LOCUS_SQLITE_DONE {
            logSQLiteError("\(op) (rc=\(rc))")
            return false
        }
        return true
    }

    /// Surfaces SQLite errors via NSLog so silent corruption doesn't go
    /// undetected. Mirrors the visibility we get on Android via Log.e on
    /// the storage layer. Caller must already hold `queue`.
    private func logSQLiteError(_ operation: String) {
        guard let db = self.db, let raw = locus_sqlite3_errmsg(db) else {
            NSLog("[locus.SQLiteStorage] %@ failed (no errmsg available)", operation)
            return
        }
        NSLog("[locus.SQLiteStorage] %@ failed: %s", operation, raw)
    }

    /// Encodes `object` as a JSON string, logging on failure. Returns nil
    /// when serialization or UTF-8 conversion fails so insert paths can
    /// short-circuit instead of silently dropping rows on the floor.
    private func serializeJSON(_ object: Any, op: String) -> String? {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: object)
        } catch {
            NSLog("[locus.SQLiteStorage] %@ JSON serialization failed: %@", op, error.localizedDescription)
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            NSLog("[locus.SQLiteStorage] %@ JSON utf8 decode failed", op)
            return nil
        }
        return string
    }
    
    /// Caller must already hold `queue`.
    private func createTables() {
        guard db != nil else { return }

        let createStatements = [
            """
            CREATE TABLE IF NOT EXISTS locations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT UNIQUE NOT NULL,
                payload TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                created_at REAL DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS geofences (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                identifier TEXT UNIQUE NOT NULL,
                payload TEXT NOT NULL,
                created_at REAL DEFAULT (strftime('%s', 'now'))
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS queue (
                id TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                type TEXT,
                idempotency_key TEXT,
                retry_count INTEGER DEFAULT 0,
                next_retry_at TEXT,
                created_at TEXT NOT NULL,
                failed_at TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS dead_letter (
                id TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                type TEXT,
                idempotency_key TEXT,
                retry_count INTEGER DEFAULT 0,
                failed_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                level TEXT NOT NULL,
                message TEXT NOT NULL,
                tag TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS migration_state (
                key TEXT PRIMARY KEY,
                completed_at REAL NOT NULL DEFAULT (strftime('%s', 'now'))
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_locations_timestamp ON locations(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_queue_retry ON queue(next_retry_at);",
            "CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp);"
        ]

        for sql in createStatements {
            _executeStatementOnQueue(sql)
        }
    }
    
    private func executeStatement(_ sql: String) {
        queue.sync {
            _executeStatementOnQueue(sql)
        }
    }

    /// Executes a SQL statement assuming we are already on the serial queue.
    /// Use this from methods that already dispatch to queue.async.
    private func _executeStatementOnQueue(_ sql: String) {
        guard let db = self.db else { return }
        var statement: OpaquePointer?
        if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
            stepChecked(statement, op: "execute (\(sql.prefix(60)))")
        } else {
            logSQLiteError("execute prepare (\(sql.prefix(60)))")
        }
        locus_sqlite3_finalize(statement)
    }
    
    // MARK: - Migration from UserDefaults
    
    /// Caller must already hold `queue`.
    private func migrateFromUserDefaults() {
        let migrationKey = "locus_sqlite_migrated"
        let migrationReceipt = "user_defaults_v1"
        guard !userDefaults.bool(forKey: migrationKey) else { return }

        // A crash can occur after SQLite commits but before UserDefaults source
        // cleanup. The durable DB receipt makes that window idempotent, including
        // legacy log rows that do not have a natural unique identifier.
        let wasAlreadyCommitted = migrationReceiptExistsOnQueue(migrationReceipt)
        if wasAlreadyCommitted {
            clearLegacyUserDefaults(migrationKey: migrationKey)
            return
        }

        let locations = userDefaults.array(forKey: "bg_locations") as? [[String: Any]] ?? []
        let geofences = userDefaults.array(forKey: "bg_geofences") as? [[String: Any]] ?? []
        let queueItems = userDefaults.array(forKey: "bg_queue") as? [[String: Any]] ?? []
        let log = userDefaults.string(forKey: "bg_log") ?? ""

        let committed = commitLegacyRowsOnQueue(
            locations: locations,
            geofences: geofences,
            queueItems: queueItems,
            log: log,
            receipt: migrationReceipt
        )

        guard committed else { return }
        clearLegacyUserDefaults(migrationKey: migrationKey)
    }

    /// Caller must already hold `queue`.
    private func commitLegacyRowsOnQueue(
        locations: [[String: Any]],
        geofences: [[String: Any]],
        queueItems: [[String: Any]],
        log: String,
        receipt migrationReceipt: String
    ) -> Bool {
        guard let db = self.db else { return false }
        guard locus_sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == LOCUS_SQLITE_OK else {
            self.logSQLiteError("legacy migration begin")
            return false
        }

        var succeeded = true
        for location in locations {
            succeeded = self.insertLocationOnQueue(location) && succeeded
        }
        for geofence in geofences {
            succeeded = self.insertGeofenceOnQueue(geofence) && succeeded
        }
        for item in queueItems {
            succeeded = self.insertQueueItemOnQueue(item) && succeeded
        }
        for line in log.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count == 3, let rawTimestamp = Double(parts[0]) else {
                // Old releases skipped malformed log rows. Preserve that
                // backwards-compatible best-effort behavior so one corrupt
                // diagnostic line cannot hide valid tracking data forever.
                NSLog("[locus.SQLiteStorage] Skipping malformed legacy log row")
                continue
            }
            let timestampMs = rawTimestamp < 1_000_000_000_000
                ? Int64(rawTimestamp * 1000)
                : Int64(rawTimestamp)
            succeeded = self.insertLogOnQueue(
                timestampMs: timestampMs,
                level: String(parts[1]),
                message: String(parts[2]),
                tag: "locus"
            ) && succeeded
        }
        succeeded = self.insertMigrationReceiptOnQueue(migrationReceipt) && succeeded

        if succeeded && locus_sqlite3_exec(db, "COMMIT", nil, nil, nil) == LOCUS_SQLITE_OK {
            self.walCheckpointOnQueue()
            return true
        }
        let rollbackStatus = locus_sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
        if rollbackStatus != LOCUS_SQLITE_OK {
            self.logSQLiteError("legacy migration rollback")
        }
        return false
    }

    private func clearLegacyUserDefaults(migrationKey: String) {
        userDefaults.removeObject(forKey: "bg_locations")
        userDefaults.removeObject(forKey: "bg_geofences")
        userDefaults.removeObject(forKey: "bg_queue")
        userDefaults.removeObject(forKey: "bg_log")
        userDefaults.set(true, forKey: migrationKey)
    }

    private func migrationReceiptExistsOnQueue(_ key: String) -> Bool {
        guard let db else { return false }
        let sql = "SELECT 1 FROM migration_state WHERE key = ? LIMIT 1"
        var statement: OpaquePointer?
        guard locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK else {
            logSQLiteError("migration receipt select prepare")
            locus_sqlite3_finalize(statement)
            return false
        }
        defer { locus_sqlite3_finalize(statement) }
        locus_sqlite3_bind_text(statement, 1, key, -1, SQLiteStorage.SQLITE_TRANSIENT)
        return locus_sqlite3_step(statement) == LOCUS_SQLITE_ROW
    }

    private func insertMigrationReceiptOnQueue(_ key: String) -> Bool {
        guard let db else { return false }
        let sql = "INSERT OR REPLACE INTO migration_state (key) VALUES (?)"
        var statement: OpaquePointer?
        guard locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK else {
            logSQLiteError("migration receipt insert prepare")
            locus_sqlite3_finalize(statement)
            return false
        }
        defer { locus_sqlite3_finalize(statement) }
        locus_sqlite3_bind_text(statement, 1, key, -1, SQLiteStorage.SQLITE_TRANSIENT)
        return stepChecked(statement, op: "migration receipt insert")
    }
    
    // MARK: - Locations

    /// Inserts a location while already on the SQLite queue. Kept result-bearing
    /// so startup migration can commit or preserve its source atomically.
    private func insertLocationOnQueue(_ payload: [String: Any]) -> Bool {
        guard let db = db else { return false }
        let uuid = payload["uuid"] as? String ?? UUID().uuidString
        let timestamp = payload["timestamp"] as? String ?? ISO8601DateFormatter().string(from: Date())
        guard let jsonString = serializeJSON(payload, op: "insertLocation") else { return false }

        let sql = "INSERT OR REPLACE INTO locations (uuid, payload, timestamp) VALUES (?, ?, ?)"
        var statement: OpaquePointer?
        guard locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK else {
            logSQLiteError("insertLocation prepare")
            locus_sqlite3_finalize(statement)
            return false
        }
        defer { locus_sqlite3_finalize(statement) }
        locus_sqlite3_bind_text(statement, 1, uuid, -1, SQLiteStorage.SQLITE_TRANSIENT)
        locus_sqlite3_bind_text(statement, 2, jsonString, -1, SQLiteStorage.SQLITE_TRANSIENT)
        locus_sqlite3_bind_text(statement, 3, timestamp, -1, SQLiteStorage.SQLITE_TRANSIENT)
        return stepChecked(statement, op: "insertLocation")
    }

    /// Writes the location, or holds it in memory (newest `maximumHeldLocations`)
    /// while storage is unavailable. Held fixes are written in order, each
    /// followed by its completion, once a retry succeeds. A process kill while
    /// fixes are held loses them.
    func insertLocation(_ payload: [String: Any], completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.retryPreparationIfDueOnQueue()
            if self.db != nil {
                // Fixes whose replay failed stay ahead of this one.
                self.flushHeldLocationsOnQueue()
            }
            let location = HeldLocation(payload: payload, completion: completion)
            guard self.db != nil, self.heldLocations.isEmpty else {
                self.holdLocationOnQueue(location)
                return
            }
            self.writeLocationOnQueue(location)
        }
    }

    /// Caller must already hold `queue`.
    private func holdLocationOnQueue(_ location: HeldLocation) {
        heldLocations.append(location)
        if heldLocations.count > Self.maximumHeldLocations {
            heldLocations.removeFirst(heldLocations.count - Self.maximumHeldLocations)
            NSLog("[locus.SQLiteStorage] Held location limit of %d exceeded; dropped the oldest unsaved fix", Self.maximumHeldLocations)
        }
        NSLog("[locus.SQLiteStorage] Holding %d unsaved fix(es) until storage accepts writes; last preparation failure: %@", heldLocations.count, preparationFailure)
    }

    /// Writes held fixes oldest first and stops at the first failed insert, so
    /// that fix and every later one stay held in order for the next attempt.
    /// A fix that fails `maximumHeldWriteAttempts` times is dropped and logged.
    /// Applies the retention limits requested meanwhile once any fix was
    /// written. Caller must already hold `queue` and have an open database.
    private func flushHeldLocationsOnQueue() {
        guard !heldLocations.isEmpty else { return }
        NSLog("[locus.SQLiteStorage] Writing %d held fix(es)", heldLocations.count)
        var written = 0
        while var location = heldLocations.first {
            guard writeLocationOnQueue(location) else {
                location.failedWrites += 1
                if location.failedWrites >= Self.maximumHeldWriteAttempts {
                    heldLocations.removeFirst()
                    NSLog("[locus.SQLiteStorage] Dropped a held fix after %d failed writes", location.failedWrites)
                    continue
                }
                heldLocations[0] = location
                NSLog("[locus.SQLiteStorage] Held fix write failed; %d fix(es) stay held", heldLocations.count)
                break
            }
            heldLocations.removeFirst()
            written += 1
        }
        if written > 0, let pendingPrune {
            self.pendingPrune = nil
            pruneLocationsOnQueue(maxDays: pendingPrune.maxDays, maxRecords: pendingPrune.maxRecords)
        }
    }

    /// Runs the location's completion on the main queue once, only after the
    /// insert succeeded. Returns false when the insert failed.
    /// Caller must already hold `queue` and have an open database.
    @discardableResult
    private func writeLocationOnQueue(_ location: HeldLocation) -> Bool {
        guard insertLocationOnQueue(location.payload) else { return false }
        walCheckpointOnQueue()
        if let completion = location.completion {
            DispatchQueue.main.async {
                completion()
            }
        }
        return true
    }

    func readLocations(limit: Int = 0) -> [[String: Any]] {
        var results: [[String: Any]] = []
        
        queue.sync {
            self.retryPreparationIfDueOnQueue()
            guard let db = self.db else { return }
            
            var sql = "SELECT payload FROM locations ORDER BY timestamp DESC"
            if limit > 0 {
                sql += " LIMIT \(limit)"
            }
            
            var statement: OpaquePointer?
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                while locus_sqlite3_step(statement) == LOCUS_SQLITE_ROW {
                    if let jsonPtr = locus_sqlite3_column_text(statement, 0),
                       let data = String(cString: jsonPtr).data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        results.append(payload)
                    }
                }
            }
            locus_sqlite3_finalize(statement)
        }
        
        return results
    }
    
    /// Uses a separate read-only connection so long scans never block writes.
    func queryLocations(_ query: StoredLocationQuery,
                        completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        // Hop through the write queue so earlier writes are visible.
        queue.async {
            self.retryPreparationIfDueOnQueue()
            guard self.db != nil else {
                let failure = StorageUnavailableError(reason: self.preparationFailure)
                DispatchQueue.main.async { completion(.failure(failure)) }
                return
            }
            self.queryQueue.async {
                let result = Result { try self.queryLocationsOnQueryQueue(query) }
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    /// Caller must hold `queryQueue`.
    private func readConnectionOnQueryQueue() -> OpaquePointer? {
        if let readDb { return readDb }
        guard let encryptedDatabase else { return nil }
        let connection: OpaquePointer
        do {
            connection = try encryptedDatabase.open(readOnly: true)
        } catch {
            NSLog("[locus.SQLiteStorage] Encrypted read connection unavailable: %@", error.localizedDescription)
            return nil
        }
        locus_sqlite3_busy_timeout(connection, Self.busyTimeoutMilliseconds)
        // Without JSON functions every row takes the per-row parser.
        readSupportsJSON = locus_sqlite3_exec(connection, "SELECT json_valid('{}')", nil, nil, nil) == LOCUS_SQLITE_OK
        readDb = connection
        return connection
    }

    /// Rows whose payload timestamp equals the whole-second UTC `timestamp` column
    /// filter and sort on that column; all others use the per-row parser.
    /// Binds: from, to, limit, offset.
    private func locationQuerySQL(for query: StoredLocationQuery) -> String {
        // json_extract raises an error on malformed JSON.
        let canonical = readSupportsJSON ? """
            CASE WHEN json_valid(payload) THEN
                json_extract(payload, '$.timestamp') IS timestamp
                AND strftime('%Y-%m-%dT%H:%M:%SZ', timestamp) IS timestamp
            ELSE 0 END
            """ : "0"
        let columnMicros = "CAST(strftime('%s', timestamp) AS INTEGER) * \(StoredLocationQuery.microsPerSecond)"
        let parsed = "locus_query_timestamp(payload)"
        // LIMIT -1 stops SQLite inlining sort_key and evaluating it twice.
        return """
            SELECT payload FROM (
                SELECT id, payload,
                    CASE WHEN \(canonical) THEN
                        CASE WHEN \(columnMicros) BETWEEN ? AND ?
                            THEN \(query.filtersPayload ? parsed : columnMicros) END
                    ELSE \(parsed) END AS sort_key
                FROM locations
                LIMIT -1
            )
            WHERE sort_key IS NOT NULL
            ORDER BY sort_key \(query.ascending ? "ASC" : "DESC"), id ASC
            LIMIT ? OFFSET ?
            """
    }

    private func queryLocationsOnQueryQueue(_ query: StoredLocationQuery) throws -> [[String: Any]] {
        if let limit = query.limit, limit <= 0 { return [] }
        guard let db = readConnectionOnQueryQueue() else {
            throw StoredLocationQuery.error("Location database is unavailable")
        }
        func databaseError(_ operation: String) -> NSError {
            StoredLocationQuery.error("\(operation): \(String(cString: locus_sqlite3_errmsg(db)))")
        }
        // SQLite owns the retained query until the function is unregistered. v2
        // also invokes the destructor if registration fails.
        let context = Unmanaged.passRetained(query).toOpaque()
        let registration = locus_sqlite3_create_function_v2(
            db, "locus_query_timestamp", 1, LOCUS_SQLITE_UTF8 | LOCUS_SQLITE_DETERMINISTIC,
            context, { context, _, values in
                // Release JSON/regex Foundation temporaries after each row,
                // rather than retaining them until a large scan completes.
                autoreleasepool {
                    guard let context, let values, let userData = locus_sqlite3_user_data(context) else {
                        locus_sqlite3_result_error(context, "Missing location query context", -1)
                        return
                    }
                    let query = Unmanaged<StoredLocationQuery>.fromOpaque(userData).takeUnretainedValue()
                    if let timestamp = query.matchingTimestamp(values[0]) {
                        locus_sqlite3_result_int64(context, timestamp)
                    } else {
                        locus_sqlite3_result_null(context)
                    }
                }
            }, nil, nil, { context in
                if let context {
                    Unmanaged<StoredLocationQuery>.fromOpaque(context).release()
                }
            }
        )
        guard registration == LOCUS_SQLITE_OK else { throw databaseError("Register location query") }
        let result: Result<[[String: Any]], Error> = Result {
            let sql = locationQuerySQL(for: query)
            let bindings: [Int64] = [
                query.from ?? Int64.min,
                query.to ?? Int64.max,
                query.limit ?? -1,
                query.offset,
            ]
            var statement: OpaquePointer?
            guard locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK else {
                locus_sqlite3_finalize(statement)
                throw databaseError("Prepare location query")
            }
            defer { locus_sqlite3_finalize(statement) }
            for (index, value) in bindings.enumerated() {
                guard locus_sqlite3_bind_int64(statement, Int32(index + 1), value) == LOCUS_SQLITE_OK else {
                    throw databaseError("Bind location query")
                }
            }
            var rows: [[String: Any]] = []
            while true {
                let step = locus_sqlite3_step(statement)
                if step == LOCUS_SQLITE_DONE { break }
                guard step == LOCUS_SQLITE_ROW else { throw databaseError("Read location query") }
                guard let bytes = locus_sqlite3_column_text(statement, 0),
                      let payload = try? JSONSerialization.jsonObject(
                        with: Data(bytes: bytes, count: Int(locus_sqlite3_column_bytes(statement, 0)))
                      ) as? [String: Any] else {
                    NSLog("[locus.SQLiteStorage] queryLocations skipped an undecodable stored location")
                    continue
                }
                rows.append(payload)
            }
            return rows
        }
        // The statement has been finalized before unregistering and releasing its
        // callback context, including on bind, step, and JSON decoding failures.
        let unregistration = locus_sqlite3_create_function_v2(
            db, "locus_query_timestamp", 1, LOCUS_SQLITE_UTF8 | LOCUS_SQLITE_DETERMINISTIC,
            nil, nil, nil, nil, nil
        )
        guard unregistration == LOCUS_SQLITE_OK else { throw databaseError("Unregister location query") }
        return try result.get()
    }

    func removeLocations(_ uuids: [String]) {
        guard !uuids.isEmpty else { return }

        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let placeholders = uuids.map { _ in "?" }.joined(separator: ", ")
            let sql = "DELETE FROM locations WHERE uuid IN (\(placeholders))"

            var statement: OpaquePointer?
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                for (index, uuid) in uuids.enumerated() {
                    locus_sqlite3_bind_text(statement, Int32(index + 1), uuid, -1, SQLiteStorage.SQLITE_TRANSIENT)
                }
                self.stepChecked(statement, op: "removeLocations")
            } else {
                self.logSQLiteError("removeLocations prepare")
            }
            locus_sqlite3_finalize(statement)
            self.walCheckpointOnQueue()
        }
    }

    func clearLocations() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self._executeStatementOnQueue("DELETE FROM locations")
            self.walCheckpointOnQueue()
        }
    }

    func pruneLocations(maxDays: Int, maxRecords: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if !self.heldLocations.isEmpty {
                // Held fixes are written later; prune again once they are.
                self.pendingPrune = (maxDays, maxRecords)
            }
            guard self.db != nil else { return }
            self.pruneLocationsOnQueue(maxDays: maxDays, maxRecords: maxRecords)
        }
    }

    /// Caller must already hold `queue` and have an open database.
    private func pruneLocationsOnQueue(maxDays: Int, maxRecords: Int) {
        guard let db = self.db else { return }

        // Prune by age
        if maxDays > 0 {
            let cutoff = Date().addingTimeInterval(TimeInterval(-maxDays * 24 * 60 * 60))
            let cutoffString = ISO8601DateFormatter().string(from: cutoff)

            let sql = "DELETE FROM locations WHERE timestamp < ?"
            var statement: OpaquePointer?
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                locus_sqlite3_bind_text(statement, 1, cutoffString, -1, SQLiteStorage.SQLITE_TRANSIENT)
                self.stepChecked(statement, op: "pruneLocations(age)")
            } else {
                self.logSQLiteError("pruneLocations(age) prepare")
            }
            locus_sqlite3_finalize(statement)
        }

        // Prune by count
        if maxRecords > 0 {
            let sql = """
                DELETE FROM locations WHERE id NOT IN (
                    SELECT id FROM locations ORDER BY timestamp DESC LIMIT ?
                )
            """
            var statement: OpaquePointer?
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                locus_sqlite3_bind_int(statement, 1, Int32(maxRecords))
                self.stepChecked(statement, op: "pruneLocations(count)")
            } else {
                self.logSQLiteError("pruneLocations(count) prepare")
            }
            locus_sqlite3_finalize(statement)
        }
        self.walCheckpointOnQueue()
    }

    func locationCount() -> Int {
        var count = 0
        queue.sync {
            self.retryPreparationIfDueOnQueue()
            guard let db = self.db else { return }
            
            let sql = "SELECT COUNT(*) FROM locations"
            var statement: OpaquePointer?
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                if locus_sqlite3_step(statement) == LOCUS_SQLITE_ROW {
                    count = Int(locus_sqlite3_column_int(statement, 0))
                }
            }
            locus_sqlite3_finalize(statement)
        }
        return count
    }
    
    // MARK: - Geofences

    private func insertGeofenceOnQueue(_ payload: [String: Any]) -> Bool {
        guard let db = db else { return false }
        guard let identifier = payload["identifier"] as? String else {
            NSLog("[locus.SQLiteStorage] insertGeofence skipped: missing 'identifier'")
            return false
        }
        guard let jsonString = serializeJSON(payload, op: "insertGeofence") else { return false }

        let sql = "INSERT OR REPLACE INTO geofences (identifier, payload) VALUES (?, ?)"
        var statement: OpaquePointer?
        guard locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK else {
            logSQLiteError("insertGeofence prepare")
            locus_sqlite3_finalize(statement)
            return false
        }
        defer { locus_sqlite3_finalize(statement) }
        locus_sqlite3_bind_text(statement, 1, identifier, -1, SQLiteStorage.SQLITE_TRANSIENT)
        locus_sqlite3_bind_text(statement, 2, jsonString, -1, SQLiteStorage.SQLITE_TRANSIENT)
        return stepChecked(statement, op: "insertGeofence")
    }
    
    func insertGeofence(_ payload: [String: Any]) {
        queue.async { [weak self] in
            guard let self = self, self.insertGeofenceOnQueue(payload) else { return }
            self.walCheckpointOnQueue()
        }
    }

    func readGeofences() -> [[String: Any]] {
        var results: [[String: Any]] = []
        
        queue.sync {
            self.retryPreparationIfDueOnQueue()
            guard let db = self.db else { return }
            
            let sql = "SELECT payload FROM geofences"
            var statement: OpaquePointer?
            
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                while locus_sqlite3_step(statement) == LOCUS_SQLITE_ROW {
                    if let jsonPtr = locus_sqlite3_column_text(statement, 0),
                       let data = String(cString: jsonPtr).data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        results.append(payload)
                    }
                }
            }
            locus_sqlite3_finalize(statement)
        }
        
        return results
    }
    
    func removeGeofence(_ identifier: String) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = "DELETE FROM geofences WHERE identifier = ?"
            var statement: OpaquePointer?

            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                locus_sqlite3_bind_text(statement, 1, identifier, -1, SQLiteStorage.SQLITE_TRANSIENT)
                self.stepChecked(statement, op: "removeGeofence")
            } else {
                self.logSQLiteError("removeGeofence prepare")
            }
            locus_sqlite3_finalize(statement)
            self.walCheckpointOnQueue()
        }
    }
    
    func clearGeofences() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self._executeStatementOnQueue("DELETE FROM geofences")
            // Match the WAL-checkpoint cadence of the other write paths
            // (insertQueueItem, removeLocations, pruneLocations, etc.) so a
            // bulk geofence reset doesn't strand WAL pages until the next
            // unrelated write triggers a checkpoint.
            self.walCheckpointOnQueue()
        }
    }
    
    // MARK: - Queue

    private func insertQueueItemOnQueue(_ item: [String: Any]) -> Bool {
        guard let db = db else { return false }
        let id = item["id"] as? String ?? UUID().uuidString
        let type = item["type"] as? String
        let idempotencyKey = item["idempotencyKey"] as? String
        let retryCount = item["retryCount"] as? Int ?? 0
        let nextRetryAt = item["nextRetryAt"] as? String
        let createdAt = item["created"] as? String ?? ISO8601DateFormatter().string(from: Date())
        guard let payloadData = item["payload"] else {
            NSLog("[locus.SQLiteStorage] insertQueueItem skipped: missing 'payload'")
            return false
        }
        guard let jsonString = serializeJSON(payloadData, op: "insertQueueItem") else { return false }

        let sql = """
            INSERT OR REPLACE INTO queue
            (id, payload, type, idempotency_key, retry_count, next_retry_at, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK else {
            logSQLiteError("insertQueueItem prepare")
            locus_sqlite3_finalize(statement)
            return false
        }
        defer { locus_sqlite3_finalize(statement) }
        locus_sqlite3_bind_text(statement, 1, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
        locus_sqlite3_bind_text(statement, 2, jsonString, -1, SQLiteStorage.SQLITE_TRANSIENT)
        if let type { locus_sqlite3_bind_text(statement, 3, type, -1, SQLiteStorage.SQLITE_TRANSIENT) }
        else { locus_sqlite3_bind_null(statement, 3) }
        if let idempotencyKey { locus_sqlite3_bind_text(statement, 4, idempotencyKey, -1, SQLiteStorage.SQLITE_TRANSIENT) }
        else { locus_sqlite3_bind_null(statement, 4) }
        locus_sqlite3_bind_int(statement, 5, Int32(retryCount))
        if let nextRetryAt { locus_sqlite3_bind_text(statement, 6, nextRetryAt, -1, SQLiteStorage.SQLITE_TRANSIENT) }
        else { locus_sqlite3_bind_null(statement, 6) }
        locus_sqlite3_bind_text(statement, 7, createdAt, -1, SQLiteStorage.SQLITE_TRANSIENT)
        return stepChecked(statement, op: "insertQueueItem")
    }

    func insertQueueItem(_ item: [String: Any]) {
        queue.async { [weak self] in
            guard let self = self, self.insertQueueItemOnQueue(item) else { return }
            self.walCheckpointOnQueue()
        }
    }

    func readQueue() -> [[String: Any]] {
        var results: [[String: Any]] = []
        
        queue.sync {
            self.retryPreparationIfDueOnQueue()
            guard let db = self.db else { return }
            
            let sql = "SELECT id, payload, type, idempotency_key, retry_count, next_retry_at, created_at FROM queue ORDER BY created_at"
            var statement: OpaquePointer?
            
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                while locus_sqlite3_step(statement) == LOCUS_SQLITE_ROW {
                    var item: [String: Any] = [:]
                    
                    if let idPtr = locus_sqlite3_column_text(statement, 0) {
                        item["id"] = String(cString: idPtr)
                    }
                    if let payloadPtr = locus_sqlite3_column_text(statement, 1),
                       let data = String(cString: payloadPtr).data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: data) {
                        item["payload"] = payload
                    }
                    if let typePtr = locus_sqlite3_column_text(statement, 2) {
                        item["type"] = String(cString: typePtr)
                    }
                    if let keyPtr = locus_sqlite3_column_text(statement, 3) {
                        item["idempotencyKey"] = String(cString: keyPtr)
                    }
                    item["retryCount"] = Int(locus_sqlite3_column_int(statement, 4))
                    if let retryPtr = locus_sqlite3_column_text(statement, 5) {
                        item["nextRetryAt"] = String(cString: retryPtr)
                    }
                    if let createdPtr = locus_sqlite3_column_text(statement, 6) {
                        item["created"] = String(cString: createdPtr)
                    }
                    
                    results.append(item)
                }
            }
            locus_sqlite3_finalize(statement)
        }
        
        return results
    }
    
    func removeQueueItems(_ ids: [String]) {
        guard !ids.isEmpty else { return }

        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql = "DELETE FROM queue WHERE id IN (\(placeholders))"

            var statement: OpaquePointer?
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                for (index, id) in ids.enumerated() {
                    locus_sqlite3_bind_text(statement, Int32(index + 1), id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                }
                self.stepChecked(statement, op: "removeQueueItems")
            } else {
                self.logSQLiteError("removeQueueItems prepare")
            }
            locus_sqlite3_finalize(statement)
            self.walCheckpointOnQueue()
        }
    }

    func updateQueueItem(_ id: String, retryCount: Int, nextRetryAt: String) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = "UPDATE queue SET retry_count = ?, next_retry_at = ? WHERE id = ?"
            var statement: OpaquePointer?

            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                locus_sqlite3_bind_int(statement, 1, Int32(retryCount))
                locus_sqlite3_bind_text(statement, 2, nextRetryAt, -1, SQLiteStorage.SQLITE_TRANSIENT)
                locus_sqlite3_bind_text(statement, 3, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                self.stepChecked(statement, op: "updateQueueItem")
            } else {
                self.logSQLiteError("updateQueueItem prepare")
            }
            locus_sqlite3_finalize(statement)
            self.walCheckpointOnQueue()
        }
    }

    func clearQueue() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self._executeStatementOnQueue("DELETE FROM queue")
            self.walCheckpointOnQueue()
        }
    }
    
    // MARK: - Dead Letter Queue
    
    func moveToDeadLetter(_ id: String) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            // Get item from queue
            let selectSql = "SELECT payload, type, idempotency_key, retry_count FROM queue WHERE id = ?"
            var selectStatement: OpaquePointer?
            
            var payload: String?
            var type: String?
            var idempotencyKey: String?
            var retryCount: Int = 0
            
            if locus_sqlite3_prepare_v2(db, selectSql, -1, &selectStatement, nil) == LOCUS_SQLITE_OK {
                locus_sqlite3_bind_text(selectStatement, 1, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                if locus_sqlite3_step(selectStatement) == LOCUS_SQLITE_ROW {
                    if let ptr = locus_sqlite3_column_text(selectStatement, 0) {
                        payload = String(cString: ptr)
                    }
                    if let ptr = locus_sqlite3_column_text(selectStatement, 1) {
                        type = String(cString: ptr)
                    }
                    if let ptr = locus_sqlite3_column_text(selectStatement, 2) {
                        idempotencyKey = String(cString: ptr)
                    }
                    retryCount = Int(locus_sqlite3_column_int(selectStatement, 3))
                }
            }
            locus_sqlite3_finalize(selectStatement)
            
            guard let payload = payload else { return }
            
            // Insert into dead letter
            let insertSql = """
                INSERT INTO dead_letter (id, payload, type, idempotency_key, retry_count, failed_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """
            var insertStatement: OpaquePointer?
            let failedAt = ISO8601DateFormatter().string(from: Date())
            
            if locus_sqlite3_prepare_v2(db, insertSql, -1, &insertStatement, nil) == LOCUS_SQLITE_OK {
                locus_sqlite3_bind_text(insertStatement, 1, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                locus_sqlite3_bind_text(insertStatement, 2, payload, -1, SQLiteStorage.SQLITE_TRANSIENT)
                if let type = type {
                    locus_sqlite3_bind_text(insertStatement, 3, type, -1, SQLiteStorage.SQLITE_TRANSIENT)
                } else {
                    locus_sqlite3_bind_null(insertStatement, 3)
                }
                if let key = idempotencyKey {
                    locus_sqlite3_bind_text(insertStatement, 4, key, -1, SQLiteStorage.SQLITE_TRANSIENT)
                } else {
                    locus_sqlite3_bind_null(insertStatement, 4)
                }
                locus_sqlite3_bind_int(insertStatement, 5, Int32(retryCount))
                locus_sqlite3_bind_text(insertStatement, 6, failedAt, -1, SQLiteStorage.SQLITE_TRANSIENT)
                self.stepChecked(insertStatement, op: "moveToDeadLetter(insert)")
            } else {
                self.logSQLiteError("moveToDeadLetter(insert) prepare")
            }
            locus_sqlite3_finalize(insertStatement)

            // Remove from queue (parameterized to prevent SQL injection)
            let deleteSql = "DELETE FROM queue WHERE id = ?"
            var deleteStatement: OpaquePointer?
            if locus_sqlite3_prepare_v2(db, deleteSql, -1, &deleteStatement, nil) == LOCUS_SQLITE_OK {
                locus_sqlite3_bind_text(deleteStatement, 1, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                self.stepChecked(deleteStatement, op: "moveToDeadLetter(delete)")
            } else {
                self.logSQLiteError("moveToDeadLetter(delete) prepare")
            }
            locus_sqlite3_finalize(deleteStatement)
            
            // Keep dead letter bounded
            self._executeStatementOnQueue("""
                DELETE FROM dead_letter WHERE id NOT IN (
                    SELECT id FROM dead_letter ORDER BY failed_at DESC LIMIT 100
                )
            """)
        }
    }
    
    func readDeadLetter() -> [[String: Any]] {
        var results: [[String: Any]] = []
        
        queue.sync {
            self.retryPreparationIfDueOnQueue()
            guard let db = self.db else { return }
            
            let sql = "SELECT id, payload, type, idempotency_key, retry_count, failed_at FROM dead_letter ORDER BY failed_at DESC"
            var statement: OpaquePointer?
            
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                while locus_sqlite3_step(statement) == LOCUS_SQLITE_ROW {
                    var item: [String: Any] = [:]
                    
                    if let ptr = locus_sqlite3_column_text(statement, 0) {
                        item["id"] = String(cString: ptr)
                    }
                    if let payloadPtr = locus_sqlite3_column_text(statement, 1),
                       let data = String(cString: payloadPtr).data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: data) {
                        item["payload"] = payload
                    }
                    if let ptr = locus_sqlite3_column_text(statement, 2) {
                        item["type"] = String(cString: ptr)
                    }
                    if let ptr = locus_sqlite3_column_text(statement, 3) {
                        item["idempotencyKey"] = String(cString: ptr)
                    }
                    item["retryCount"] = Int(locus_sqlite3_column_int(statement, 4))
                    if let ptr = locus_sqlite3_column_text(statement, 5) {
                        item["failedAt"] = String(cString: ptr)
                    }
                    
                    results.append(item)
                }
            }
            locus_sqlite3_finalize(statement)
        }
        
        return results
    }
    
    func clearDeadLetter() {
        queue.async { [weak self] in
            self?._executeStatementOnQueue("DELETE FROM dead_letter")
        }
    }

    // MARK: - Logs

    private func insertLogOnQueue(
        timestampMs: Int64,
        level: String,
        message: String,
        tag: String?
    ) -> Bool {
        guard let db = db else { return false }
        let sql = "INSERT INTO logs (timestamp, level, message, tag) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK else {
            logSQLiteError("insertLog prepare")
            locus_sqlite3_finalize(statement)
            return false
        }
        defer { locus_sqlite3_finalize(statement) }
        locus_sqlite3_bind_int64(statement, 1, timestampMs)
        locus_sqlite3_bind_text(statement, 2, level, -1, SQLiteStorage.SQLITE_TRANSIENT)
        locus_sqlite3_bind_text(statement, 3, message, -1, SQLiteStorage.SQLITE_TRANSIENT)
        if let tag { locus_sqlite3_bind_text(statement, 4, tag, -1, SQLiteStorage.SQLITE_TRANSIENT) }
        else { locus_sqlite3_bind_null(statement, 4) }
        return stepChecked(statement, op: "insertLog")
    }

    func insertLog(timestampMs: Int64, level: String, message: String, tag: String? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            _ = self.insertLogOnQueue(
                timestampMs: timestampMs,
                level: level,
                message: message,
                tag: tag
            )
        }
    }

    func readLogs(limit: Int = 0) -> [[String: Any]] {
        var results: [[String: Any]] = []

        queue.sync {
            self.retryPreparationIfDueOnQueue()
            guard let db = self.db else { return }

            var sql = "SELECT timestamp, level, message, tag FROM logs ORDER BY timestamp DESC"
            if limit > 0 {
                sql += " LIMIT \(limit)"
            }

            var statement: OpaquePointer?
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                while locus_sqlite3_step(statement) == LOCUS_SQLITE_ROW {
                    var item: [String: Any] = [:]
                    item["timestamp"] = Int64(locus_sqlite3_column_int64(statement, 0))
                    if let ptr = locus_sqlite3_column_text(statement, 1) {
                        item["level"] = String(cString: ptr)
                    }
                    if let ptr = locus_sqlite3_column_text(statement, 2) {
                        item["message"] = String(cString: ptr)
                    }
                    if let ptr = locus_sqlite3_column_text(statement, 3) {
                        item["tag"] = String(cString: ptr)
                    }
                    results.append(item)
                }
            }
            locus_sqlite3_finalize(statement)
        }

        return results
    }

    func pruneLogs(maxDays: Int) {
        guard maxDays > 0 else { return }
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(maxDays * 24 * 60 * 60 * 1000)
            let sql = "DELETE FROM logs WHERE timestamp < ?"
            var statement: OpaquePointer?
            if locus_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == LOCUS_SQLITE_OK {
                locus_sqlite3_bind_int64(statement, 1, cutoff)
                self.stepChecked(statement, op: "pruneLogs")
            } else {
                self.logSQLiteError("pruneLogs prepare")
            }
            locus_sqlite3_finalize(statement)
        }
    }

    func clearLogs() {
        queue.async { [weak self] in
            self?._executeStatementOnQueue("DELETE FROM logs")
        }
    }
}
