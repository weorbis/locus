import Foundation
import SQLite3

/// SQLite-based storage for locations, geofences, and queue items.
/// Replaces UserDefaults to support larger datasets and better performance.
class SQLiteStorage {

    /// SQLITE_TRANSIENT equivalent: tells SQLite to copy the string data immediately.
    /// Prevents use-after-free when Swift ARC deallocates the string before sqlite3_step.
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var db: OpaquePointer?
    private static let dbName = "locus_storage.sqlite"
    private static let busyTimeoutMilliseconds: Int32 = 5_000
    private let databaseURL: URL?
    private let userDefaults: UserDefaults
    private let queue = DispatchQueue(label: "dev.locus.sqlite", qos: .utility)
    private let queryQueue = DispatchQueue(label: "dev.locus.sqlite.query", qos: .utility)
    /// Only used on `queryQueue`.
    private var readDb: OpaquePointer?
    private var readSupportsJSON = false

    init(
        databaseURL: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL()
        self.userDefaults = userDefaults
        openDatabase()
        createTables()
        migrateFromUserDefaults()
    }

    deinit {
        // Every user of the connections holds `self`, so none is running now.
        for connection in [db, readDb] {
            guard let connection else { continue }
            let closeResult = sqlite3_close(connection)
            if closeResult != SQLITE_OK {
                NSLog("[locus.SQLiteStorage] Database close failed: %d", closeResult)
            }
        }
    }
    
    // MARK: - Database Setup
    
    private func openDatabase() {
        guard let databaseURL else {
            NSLog("[locus.SQLiteStorage] Documents database directory is unavailable")
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
            db = nil
            return
        }

        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            db = nil
            return
        }
        // Durability: WAL keeps the journal independent of the main DB, and
        // synchronous=FULL fsyncs both files on commit. Together they survive
        // process kills between commit and checkpoint without data loss.
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=FULL;", nil, nil, nil)
        // Wait up to 5s on contention rather than failing fast with SQLITE_BUSY.
        sqlite3_busy_timeout(db, Self.busyTimeoutMilliseconds)
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
        sqlite3_exec(db, "PRAGMA wal_checkpoint(PASSIVE);", nil, nil, nil)
    }

    /// Steps a write statement (INSERT/UPDATE/DELETE/PRAGMA): retries on
    /// SQLITE_BUSY, expects SQLITE_DONE, and logs `sqlite3_errmsg` for any
    /// other result so DB failures aren't silent. Returns true on success.
    /// Caller must already hold `queue`.
    @discardableResult
    private func stepChecked(_ statement: OpaquePointer?, op: String) -> Bool {
        var rc = sqlite3_step(statement)
        var attempts = 0
        while rc == SQLITE_BUSY && attempts < 5 {
            attempts += 1
            rc = sqlite3_step(statement)
        }
        if rc != SQLITE_DONE {
            logSQLiteError("\(op) (rc=\(rc))")
            return false
        }
        return true
    }

    /// Surfaces SQLite errors via NSLog so silent corruption doesn't go
    /// undetected. Mirrors the visibility we get on Android via Log.e on
    /// the storage layer. Caller must already hold `queue`.
    private func logSQLiteError(_ operation: String) {
        guard let db = self.db, let raw = sqlite3_errmsg(db) else {
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
    
    private func createTables() {
        queue.sync {
            guard let _ = self.db else { return }

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
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            stepChecked(statement, op: "execute (\(sql.prefix(60)))")
        } else {
            logSQLiteError("execute prepare (\(sql.prefix(60)))")
        }
        sqlite3_finalize(statement)
    }
    
    // MARK: - Migration from UserDefaults
    
    private func migrateFromUserDefaults() {
        let migrationKey = "locus_sqlite_migrated"
        let migrationReceipt = "user_defaults_v1"
        guard !userDefaults.bool(forKey: migrationKey) else { return }

        // A crash can occur after SQLite commits but before UserDefaults source
        // cleanup. The durable DB receipt makes that window idempotent, including
        // legacy log rows that do not have a natural unique identifier.
        let wasAlreadyCommitted = queue.sync {
            migrationReceiptExistsOnQueue(migrationReceipt)
        }
        if wasAlreadyCommitted {
            clearLegacyUserDefaults(migrationKey: migrationKey)
            return
        }

        let locations = userDefaults.array(forKey: "bg_locations") as? [[String: Any]] ?? []
        let geofences = userDefaults.array(forKey: "bg_geofences") as? [[String: Any]] ?? []
        let queueItems = userDefaults.array(forKey: "bg_queue") as? [[String: Any]] ?? []
        let log = userDefaults.string(forKey: "bg_log") ?? ""

        let committed = queue.sync { () -> Bool in
            guard let db = self.db else { return false }
            guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else {
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

            if succeeded && sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK {
                self.walCheckpointOnQueue()
                return true
            }
            let rollbackStatus = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            if rollbackStatus != SQLITE_OK {
                self.logSQLiteError("legacy migration rollback")
            }
            return false
        }

        guard committed else { return }
        clearLegacyUserDefaults(migrationKey: migrationKey)
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
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("migration receipt select prepare")
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, SQLiteStorage.SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func insertMigrationReceiptOnQueue(_ key: String) -> Bool {
        guard let db else { return false }
        let sql = "INSERT OR REPLACE INTO migration_state (key) VALUES (?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("migration receipt insert prepare")
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, SQLiteStorage.SQLITE_TRANSIENT)
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
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("insertLocation prepare")
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uuid, -1, SQLiteStorage.SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, jsonString, -1, SQLiteStorage.SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, timestamp, -1, SQLiteStorage.SQLITE_TRANSIENT)
        return stepChecked(statement, op: "insertLocation")
    }

    func insertLocation(_ payload: [String: Any], completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self, self.insertLocationOnQueue(payload) else { return }
            self.walCheckpointOnQueue()

            if let completion {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
    
    func readLocations(limit: Int = 0) -> [[String: Any]] {
        var results: [[String: Any]] = []
        
        queue.sync {
            guard let db = self.db else { return }
            
            var sql = "SELECT payload FROM locations ORDER BY timestamp DESC"
            if limit > 0 {
                sql += " LIMIT \(limit)"
            }
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let jsonPtr = sqlite3_column_text(statement, 0),
                       let data = String(cString: jsonPtr).data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        results.append(payload)
                    }
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }
    
    /// Uses a separate read-only connection so long scans never block writes.
    func queryLocations(_ query: StoredLocationQuery,
                        completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        // Hop through the write queue so earlier writes are visible.
        queue.async {
            self.queryQueue.async {
                let result = Result { try self.queryLocationsOnQueryQueue(query) }
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    /// Caller must hold `queryQueue`.
    private func readConnectionOnQueryQueue() -> OpaquePointer? {
        if let readDb { return readDb }
        guard let databaseURL else { return nil }
        var connection: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            NSLog("[locus.SQLiteStorage] Read connection open failed: %@", message)
            sqlite3_close(connection)
            return nil
        }
        sqlite3_busy_timeout(connection, Self.busyTimeoutMilliseconds)
        // Without JSON functions every row takes the per-row parser.
        readSupportsJSON = sqlite3_exec(connection, "SELECT json_valid('{}')", nil, nil, nil) == SQLITE_OK
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
            StoredLocationQuery.error("\(operation): \(String(cString: sqlite3_errmsg(db)))")
        }
        // SQLite owns the retained query until the function is unregistered. v2
        // also invokes the destructor if registration fails.
        let context = Unmanaged.passRetained(query).toOpaque()
        let registration = sqlite3_create_function_v2(
            db, "locus_query_timestamp", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC,
            context, { context, _, values in
                // Release JSON/regex Foundation temporaries after each row,
                // rather than retaining them until a large scan completes.
                autoreleasepool {
                    guard let context, let values, let userData = sqlite3_user_data(context) else {
                        sqlite3_result_error(context, "Missing location query context", -1)
                        return
                    }
                    let query = Unmanaged<StoredLocationQuery>.fromOpaque(userData).takeUnretainedValue()
                    if let timestamp = query.matchingTimestamp(values[0]) {
                        sqlite3_result_int64(context, timestamp)
                    } else {
                        sqlite3_result_null(context)
                    }
                }
            }, nil, nil, { context in
                if let context {
                    Unmanaged<StoredLocationQuery>.fromOpaque(context).release()
                }
            }
        )
        guard registration == SQLITE_OK else { throw databaseError("Register location query") }
        let result: Result<[[String: Any]], Error> = Result {
            let sql = locationQuerySQL(for: query)
            let bindings = [
                query.from ?? Int64.min,
                query.to ?? Int64.max,
                query.limit ?? -1,
                query.offset,
            ]
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw databaseError("Prepare location query")
            }
            defer { sqlite3_finalize(statement) }
            for (index, value) in bindings.enumerated() {
                guard sqlite3_bind_int64(statement, Int32(index + 1), value) == SQLITE_OK else {
                    throw databaseError("Bind location query")
                }
            }
            var rows: [[String: Any]] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw databaseError("Read location query") }
                guard let bytes = sqlite3_column_text(statement, 0),
                      let payload = try? JSONSerialization.jsonObject(
                        with: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
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
        let unregistration = sqlite3_create_function_v2(
            db, "locus_query_timestamp", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC,
            nil, nil, nil, nil, nil
        )
        guard unregistration == SQLITE_OK else { throw databaseError("Unregister location query") }
        return try result.get()
    }

    func removeLocations(_ uuids: [String]) {
        guard !uuids.isEmpty else { return }

        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let placeholders = uuids.map { _ in "?" }.joined(separator: ", ")
            let sql = "DELETE FROM locations WHERE uuid IN (\(placeholders))"

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                for (index, uuid) in uuids.enumerated() {
                    sqlite3_bind_text(statement, Int32(index + 1), uuid, -1, SQLiteStorage.SQLITE_TRANSIENT)
                }
                self.stepChecked(statement, op: "removeLocations")
            } else {
                self.logSQLiteError("removeLocations prepare")
            }
            sqlite3_finalize(statement)
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
            guard let self = self, let db = self.db else { return }

            // Prune by age
            if maxDays > 0 {
                let cutoff = Date().addingTimeInterval(TimeInterval(-maxDays * 24 * 60 * 60))
                let cutoffString = ISO8601DateFormatter().string(from: cutoff)

                let sql = "DELETE FROM locations WHERE timestamp < ?"
                var statement: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_text(statement, 1, cutoffString, -1, SQLiteStorage.SQLITE_TRANSIENT)
                    self.stepChecked(statement, op: "pruneLocations(age)")
                } else {
                    self.logSQLiteError("pruneLocations(age) prepare")
                }
                sqlite3_finalize(statement)
            }

            // Prune by count
            if maxRecords > 0 {
                let sql = """
                    DELETE FROM locations WHERE id NOT IN (
                        SELECT id FROM locations ORDER BY timestamp DESC LIMIT ?
                    )
                """
                var statement: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_int(statement, 1, Int32(maxRecords))
                    self.stepChecked(statement, op: "pruneLocations(count)")
                } else {
                    self.logSQLiteError("pruneLocations(count) prepare")
                }
                sqlite3_finalize(statement)
            }
            self.walCheckpointOnQueue()
        }
    }
    
    func locationCount() -> Int {
        var count = 0
        queue.sync {
            guard let db = self.db else { return }
            
            let sql = "SELECT COUNT(*) FROM locations"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(statement, 0))
                }
            }
            sqlite3_finalize(statement)
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
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("insertGeofence prepare")
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, identifier, -1, SQLiteStorage.SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, jsonString, -1, SQLiteStorage.SQLITE_TRANSIENT)
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
            guard let db = self.db else { return }
            
            let sql = "SELECT payload FROM geofences"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let jsonPtr = sqlite3_column_text(statement, 0),
                       let data = String(cString: jsonPtr).data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        results.append(payload)
                    }
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }
    
    func removeGeofence(_ identifier: String) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = "DELETE FROM geofences WHERE identifier = ?"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, identifier, -1, SQLiteStorage.SQLITE_TRANSIENT)
                self.stepChecked(statement, op: "removeGeofence")
            } else {
                self.logSQLiteError("removeGeofence prepare")
            }
            sqlite3_finalize(statement)
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
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("insertQueueItem prepare")
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, jsonString, -1, SQLiteStorage.SQLITE_TRANSIENT)
        if let type { sqlite3_bind_text(statement, 3, type, -1, SQLiteStorage.SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(statement, 3) }
        if let idempotencyKey { sqlite3_bind_text(statement, 4, idempotencyKey, -1, SQLiteStorage.SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(statement, 4) }
        sqlite3_bind_int(statement, 5, Int32(retryCount))
        if let nextRetryAt { sqlite3_bind_text(statement, 6, nextRetryAt, -1, SQLiteStorage.SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(statement, 6) }
        sqlite3_bind_text(statement, 7, createdAt, -1, SQLiteStorage.SQLITE_TRANSIENT)
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
            guard let db = self.db else { return }
            
            let sql = "SELECT id, payload, type, idempotency_key, retry_count, next_retry_at, created_at FROM queue ORDER BY created_at"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    var item: [String: Any] = [:]
                    
                    if let idPtr = sqlite3_column_text(statement, 0) {
                        item["id"] = String(cString: idPtr)
                    }
                    if let payloadPtr = sqlite3_column_text(statement, 1),
                       let data = String(cString: payloadPtr).data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: data) {
                        item["payload"] = payload
                    }
                    if let typePtr = sqlite3_column_text(statement, 2) {
                        item["type"] = String(cString: typePtr)
                    }
                    if let keyPtr = sqlite3_column_text(statement, 3) {
                        item["idempotencyKey"] = String(cString: keyPtr)
                    }
                    item["retryCount"] = Int(sqlite3_column_int(statement, 4))
                    if let retryPtr = sqlite3_column_text(statement, 5) {
                        item["nextRetryAt"] = String(cString: retryPtr)
                    }
                    if let createdPtr = sqlite3_column_text(statement, 6) {
                        item["created"] = String(cString: createdPtr)
                    }
                    
                    results.append(item)
                }
            }
            sqlite3_finalize(statement)
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
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                for (index, id) in ids.enumerated() {
                    sqlite3_bind_text(statement, Int32(index + 1), id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                }
                self.stepChecked(statement, op: "removeQueueItems")
            } else {
                self.logSQLiteError("removeQueueItems prepare")
            }
            sqlite3_finalize(statement)
            self.walCheckpointOnQueue()
        }
    }

    func updateQueueItem(_ id: String, retryCount: Int, nextRetryAt: String) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = "UPDATE queue SET retry_count = ?, next_retry_at = ? WHERE id = ?"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(retryCount))
                sqlite3_bind_text(statement, 2, nextRetryAt, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                self.stepChecked(statement, op: "updateQueueItem")
            } else {
                self.logSQLiteError("updateQueueItem prepare")
            }
            sqlite3_finalize(statement)
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
            
            if sqlite3_prepare_v2(db, selectSql, -1, &selectStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(selectStatement, 1, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                if sqlite3_step(selectStatement) == SQLITE_ROW {
                    if let ptr = sqlite3_column_text(selectStatement, 0) {
                        payload = String(cString: ptr)
                    }
                    if let ptr = sqlite3_column_text(selectStatement, 1) {
                        type = String(cString: ptr)
                    }
                    if let ptr = sqlite3_column_text(selectStatement, 2) {
                        idempotencyKey = String(cString: ptr)
                    }
                    retryCount = Int(sqlite3_column_int(selectStatement, 3))
                }
            }
            sqlite3_finalize(selectStatement)
            
            guard let payload = payload else { return }
            
            // Insert into dead letter
            let insertSql = """
                INSERT INTO dead_letter (id, payload, type, idempotency_key, retry_count, failed_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """
            var insertStatement: OpaquePointer?
            let failedAt = ISO8601DateFormatter().string(from: Date())
            
            if sqlite3_prepare_v2(db, insertSql, -1, &insertStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(insertStatement, 1, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStatement, 2, payload, -1, SQLiteStorage.SQLITE_TRANSIENT)
                if let type = type {
                    sqlite3_bind_text(insertStatement, 3, type, -1, SQLiteStorage.SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(insertStatement, 3)
                }
                if let key = idempotencyKey {
                    sqlite3_bind_text(insertStatement, 4, key, -1, SQLiteStorage.SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(insertStatement, 4)
                }
                sqlite3_bind_int(insertStatement, 5, Int32(retryCount))
                sqlite3_bind_text(insertStatement, 6, failedAt, -1, SQLiteStorage.SQLITE_TRANSIENT)
                self.stepChecked(insertStatement, op: "moveToDeadLetter(insert)")
            } else {
                self.logSQLiteError("moveToDeadLetter(insert) prepare")
            }
            sqlite3_finalize(insertStatement)

            // Remove from queue (parameterized to prevent SQL injection)
            let deleteSql = "DELETE FROM queue WHERE id = ?"
            var deleteStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(deleteStatement, 1, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                self.stepChecked(deleteStatement, op: "moveToDeadLetter(delete)")
            } else {
                self.logSQLiteError("moveToDeadLetter(delete) prepare")
            }
            sqlite3_finalize(deleteStatement)
            
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
            guard let db = self.db else { return }
            
            let sql = "SELECT id, payload, type, idempotency_key, retry_count, failed_at FROM dead_letter ORDER BY failed_at DESC"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    var item: [String: Any] = [:]
                    
                    if let ptr = sqlite3_column_text(statement, 0) {
                        item["id"] = String(cString: ptr)
                    }
                    if let payloadPtr = sqlite3_column_text(statement, 1),
                       let data = String(cString: payloadPtr).data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: data) {
                        item["payload"] = payload
                    }
                    if let ptr = sqlite3_column_text(statement, 2) {
                        item["type"] = String(cString: ptr)
                    }
                    if let ptr = sqlite3_column_text(statement, 3) {
                        item["idempotencyKey"] = String(cString: ptr)
                    }
                    item["retryCount"] = Int(sqlite3_column_int(statement, 4))
                    if let ptr = sqlite3_column_text(statement, 5) {
                        item["failedAt"] = String(cString: ptr)
                    }
                    
                    results.append(item)
                }
            }
            sqlite3_finalize(statement)
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
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("insertLog prepare")
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, timestampMs)
        sqlite3_bind_text(statement, 2, level, -1, SQLiteStorage.SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, message, -1, SQLiteStorage.SQLITE_TRANSIENT)
        if let tag { sqlite3_bind_text(statement, 4, tag, -1, SQLiteStorage.SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(statement, 4) }
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
            guard let db = self.db else { return }

            var sql = "SELECT timestamp, level, message, tag FROM logs ORDER BY timestamp DESC"
            if limit > 0 {
                sql += " LIMIT \(limit)"
            }

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    var item: [String: Any] = [:]
                    item["timestamp"] = Int64(sqlite3_column_int64(statement, 0))
                    if let ptr = sqlite3_column_text(statement, 1) {
                        item["level"] = String(cString: ptr)
                    }
                    if let ptr = sqlite3_column_text(statement, 2) {
                        item["message"] = String(cString: ptr)
                    }
                    if let ptr = sqlite3_column_text(statement, 3) {
                        item["tag"] = String(cString: ptr)
                    }
                    results.append(item)
                }
            }
            sqlite3_finalize(statement)
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
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, cutoff)
                self.stepChecked(statement, op: "pruneLogs")
            } else {
                self.logSQLiteError("pruneLogs prepare")
            }
            sqlite3_finalize(statement)
        }
    }

    func clearLogs() {
        queue.async { [weak self] in
            self?._executeStatementOnQueue("DELETE FROM logs")
        }
    }
}
