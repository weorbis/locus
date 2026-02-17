import Foundation
import SQLite3

/// SQLite-based storage for locations, geofences, and queue items.
/// Replaces UserDefaults to support larger datasets and better performance.
class SQLiteStorage {

    /// SQLITE_TRANSIENT equivalent: tells SQLite to copy the string data immediately.
    /// Prevents use-after-free when Swift ARC deallocates the string before sqlite3_step.
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var db: OpaquePointer?
    private let dbName = "locus_storage.sqlite"
    private let queue = DispatchQueue(label: "dev.locus.sqlite", qos: .utility)
    
    init() {
        openDatabase()
        createTables()
        migrateFromUserDefaults()
    }
    
    deinit {
        queue.sync {
            if let db = self.db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }
    
    // MARK: - Database Setup
    
    private func openDatabase() {
        let fileManager = FileManager.default
        guard let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            db = nil
            return
        }
        let dbUrl = documentsUrl.appendingPathComponent(dbName)
        
        if sqlite3_open(dbUrl.path, &db) != SQLITE_OK {
            db = nil
        }
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
            if sqlite3_step(statement) != SQLITE_DONE {
                // Statement failed
            }
        }
        sqlite3_finalize(statement)
    }
    
    // MARK: - Migration from UserDefaults
    
    private func migrateFromUserDefaults() {
        let migrationKey = "locus_sqlite_migrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        
        // Migrate locations
        if let locations = UserDefaults.standard.array(forKey: "bg_locations") as? [[String: Any]] {
            for location in locations {
                insertLocation(location)
            }
            UserDefaults.standard.removeObject(forKey: "bg_locations")
        }
        
        // Migrate geofences
        if let geofences = UserDefaults.standard.array(forKey: "bg_geofences") as? [[String: Any]] {
            for geofence in geofences {
                insertGeofence(geofence)
            }
            UserDefaults.standard.removeObject(forKey: "bg_geofences")
        }
        
        // Migrate queue
        if let queue = UserDefaults.standard.array(forKey: "bg_queue") as? [[String: Any]] {
            for item in queue {
                insertQueueItem(item)
            }
            UserDefaults.standard.removeObject(forKey: "bg_queue")
        }

        if let log = UserDefaults.standard.string(forKey: "bg_log"), !log.isEmpty {
            let lines = log.split(separator: "\n")
            for line in lines {
                let parts = line.split(separator: "|", maxSplits: 2)
                if parts.count < 3 {
                    continue
                }
                let rawTimestamp = Double(parts[0]) ?? 0
                let timestampMs: Int64
                if rawTimestamp < 1_000_000_000_000 {
                    timestampMs = Int64(rawTimestamp * 1000)
                } else {
                    timestampMs = Int64(rawTimestamp)
                }
                insertLog(timestampMs: timestampMs,
                          level: String(parts[1]),
                          message: String(parts[2]),
                          tag: "locus")
            }
            UserDefaults.standard.removeObject(forKey: "bg_log")
        }
        
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
    
    // MARK: - Locations
    
    func insertLocation(_ payload: [String: Any]) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let uuid = payload["uuid"] as? String ?? UUID().uuidString
            let timestamp = payload["timestamp"] as? String ?? ISO8601DateFormatter().string(from: Date())
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            
            let sql = "INSERT OR REPLACE INTO locations (uuid, payload, timestamp) VALUES (?, ?, ?)"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, uuid, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, jsonString, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, timestamp, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
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
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
    
    func clearLocations() {
        queue.async { [weak self] in
            self?._executeStatementOnQueue("DELETE FROM locations")
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
                    sqlite3_step(statement)
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
                    sqlite3_step(statement)
                }
                sqlite3_finalize(statement)
            }
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
    
    func insertGeofence(_ payload: [String: Any]) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            guard let identifier = payload["identifier"] as? String,
                  let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            
            let sql = "INSERT OR REPLACE INTO geofences (identifier, payload) VALUES (?, ?)"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, identifier, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, jsonString, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
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
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
    
    func clearGeofences() {
        queue.async { [weak self] in
            self?._executeStatementOnQueue("DELETE FROM geofences")
        }
    }
    
    // MARK: - Queue
    
    func insertQueueItem(_ item: [String: Any]) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let id = item["id"] as? String ?? UUID().uuidString
            let type = item["type"] as? String
            let idempotencyKey = item["idempotencyKey"] as? String
            let retryCount = item["retryCount"] as? Int ?? 0
            let nextRetryAt = item["nextRetryAt"] as? String
            let createdAt = item["created"] as? String ?? ISO8601DateFormatter().string(from: Date())
            
            guard let payloadData = item["payload"],
                  let jsonData = try? JSONSerialization.data(withJSONObject: payloadData),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            
            let sql = """
                INSERT OR REPLACE INTO queue 
                (id, payload, type, idempotency_key, retry_count, next_retry_at, created_at) 
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, jsonString, -1, SQLiteStorage.SQLITE_TRANSIENT)
                if let type = type {
                    sqlite3_bind_text(statement, 3, type, -1, SQLiteStorage.SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 3)
                }
                if let key = idempotencyKey {
                    sqlite3_bind_text(statement, 4, key, -1, SQLiteStorage.SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                sqlite3_bind_int(statement, 5, Int32(retryCount))
                if let retry = nextRetryAt {
                    sqlite3_bind_text(statement, 6, retry, -1, SQLiteStorage.SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                sqlite3_bind_text(statement, 7, createdAt, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
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
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
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
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
    
    func clearQueue() {
        queue.async { [weak self] in
            self?._executeStatementOnQueue("DELETE FROM queue")
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
                sqlite3_step(insertStatement)
            }
            sqlite3_finalize(insertStatement)
            
            // Remove from queue (parameterized to prevent SQL injection - F-004)
            let deleteSql = "DELETE FROM queue WHERE id = ?"
            var deleteStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(deleteStatement, 1, id, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_step(deleteStatement)
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

    func insertLog(timestampMs: Int64, level: String, message: String, tag: String? = nil) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = "INSERT INTO logs (timestamp, level, message, tag) VALUES (?, ?, ?, ?)"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, timestampMs)
                sqlite3_bind_text(statement, 2, level, -1, SQLiteStorage.SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, message, -1, SQLiteStorage.SQLITE_TRANSIENT)
                if let tag = tag {
                    sqlite3_bind_text(statement, 4, tag, -1, SQLiteStorage.SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
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
                sqlite3_step(statement)
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
