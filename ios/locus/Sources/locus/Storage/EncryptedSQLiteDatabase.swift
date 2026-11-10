import Darwin
import Foundation
#if canImport(LocusSQLCipher)
import LocusSQLCipher
#endif

final class EncryptedSQLiteDatabase {
    private let url: URL
    private let rawKey: String
    private let lock: DatabaseFileLock
    private static let plaintextHeader = Data("SQLite format 3\0".utf8)
    private static let busyTimeoutMilliseconds: Int32 = 5_000

    init(url: URL, key: Data) throws {
        self.url = url
        guard key.count == SecureStorage.databaseKeyByteCount else {
            throw Self.error("Validate database key length")
        }
        rawKey = "x'" + key.map { String(format: "%02x", $0) }.joined() + "'"
        lock = try DatabaseFileLock(url: url.appendingPathExtension("lock"))
        try Self.protectFiles(at: url.appendingPathExtension("lock"))

        let exists = FileManager.default.fileExists(atPath: url.path)
        let plaintext: Bool
        if exists {
            let file = try FileHandle(forReadingFrom: url)
            do {
                plaintext = try file.read(upToCount: Self.plaintextHeader.count) == Self.plaintextHeader
                try file.close()
            } catch {
                do { try file.close() } catch {
                    NSLog("[locus.SQLiteStorage] Header file close failed: %@", error.localizedDescription)
                }
                throw error
            }
        } else {
            plaintext = false
        }
        if plaintext || !exists {
            try lock.exclusive()
            if plaintext {
                try migratePlaintext()
            } else {
                try withConnection(at: url) { connection in
                    try execute(connection, "PRAGMA user_version=0", operation: "Initialize encrypted database")
                }
            }
            try lock.shared()
        }
        try Self.protectFiles(at: url)
    }

    /// True when a non-empty database file exists that is not plaintext SQLite.
    /// A file that cannot be read counts as encrypted, so an unreadable
    /// database never leads to a new key being created for it.
    static func containsEncryptedDatabase(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer {
                do { try file.close() } catch {
                    NSLog("[locus.SQLiteStorage] Header file close failed: %@", error.localizedDescription)
                }
            }
            guard let header = try file.read(upToCount: plaintextHeader.count), !header.isEmpty else { return false }
            return header != plaintextHeader
        } catch {
            NSLog("[locus.SQLiteStorage] Database header unreadable; treating it as encrypted: %@", error.localizedDescription)
            return true
        }
    }

    func open(readOnly: Bool = false) throws -> OpaquePointer {
        try open(at: url, readOnly: readOnly)
    }

    private func open(at url: URL, readOnly: Bool = false, plaintext: Bool = false) throws -> OpaquePointer {
        if !readOnly { try Self.createProtectedFile(at: url) }
        var connection: OpaquePointer?
        let flags = readOnly ? LOCUS_SQLITE_OPEN_READONLY : LOCUS_SQLITE_OPEN_READWRITE | LOCUS_SQLITE_OPEN_CREATE
        let status = locus_sqlite3_open_v2(url.path, &connection, flags, nil)
        guard status == LOCUS_SQLITE_OK, let connection else {
            if let connection { Self.close(connection) }
            throw Self.error("Open database", status)
        }
        do {
            if !plaintext {
                let status = rawKey.withCString { locus_sqlite3_key(connection, $0, Int32(rawKey.utf8.count)) }
                guard status == LOCUS_SQLITE_OK else { throw Self.error("Apply database key", status) }
            }
            let timeoutStatus = locus_sqlite3_busy_timeout(connection, Self.busyTimeoutMilliseconds)
            guard timeoutStatus == LOCUS_SQLITE_OK else { throw Self.error("Set busy timeout", timeoutStatus) }
            try execute(connection, "SELECT count(*) FROM sqlite_master", operation: "Validate database key")
            return connection
        } catch {
            Self.close(connection)
            throw error
        }
    }

    private func withConnection<T>(at url: URL, readOnly: Bool = false, body: (OpaquePointer) throws -> T) throws -> T {
        let connection = try open(at: url, readOnly: readOnly)
        let result: T
        do { result = try body(connection) } catch {
            Self.close(connection)
            throw error
        }
        let status = locus_sqlite3_close(connection)
        guard status == LOCUS_SQLITE_OK else { throw Self.error("Close database", status) }
        return result
    }

    private func migratePlaintext() throws {
        let candidate = url.appendingPathExtension("encrypted")
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let path = candidate.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }
        let source = try open(at: url, plaintext: true)
        var sourceOpen = true
        defer { if sourceOpen { Self.close(source) } }
        // DELETE checkpoints the old WAL before any file can be replaced.
        guard try strings(source, "PRAGMA journal_mode=DELETE") == ["delete"] else {
            throw Self.error("Checkpoint plaintext database")
        }
        try execute(source, "PRAGMA locking_mode=EXCLUSIVE", operation: "Lock plaintext database")
        try attach(candidate, to: source)
        try Self.protectFiles(at: candidate)
        try execute(source, "PRAGMA encrypted.synchronous=FULL", operation: "Set export durability")
        try execute(source, "BEGIN EXCLUSIVE", operation: "Begin encryption migration")
        var transactionOpen = true
        defer {
            if transactionOpen {
                let status = locus_sqlite3_exec(source, "ROLLBACK", nil, nil, nil)
                if status != LOCUS_SQLITE_OK {
                    NSLog("[locus.SQLiteStorage] Encryption rollback failed: %d", status)
                }
            }
        }
        let originalCounts = try tableCounts(source)
        let version = try integer(source, "PRAGMA user_version")
        try execute(source, "SELECT sqlcipher_export('encrypted')", operation: "Export encrypted database")
        try execute(source, "PRAGMA encrypted.user_version=\(version)", operation: "Copy schema version")
        guard try tableCounts(source, schema: "encrypted") == originalCounts,
              try strings(source, "PRAGMA encrypted.integrity_check") == ["ok"] else {
            throw Self.error("Verify encryption export")
        }
        try execute(source, "COMMIT", operation: "Commit encryption export")
        transactionOpen = false
        try execute(source, "DETACH DATABASE encrypted", operation: "Detach encrypted export")
        try withConnection(at: candidate, readOnly: true) { connection in
            guard try tableCounts(connection) == originalCounts,
                  try integer(connection, "PRAGMA user_version") == version,
                  try strings(connection, "PRAGMA integrity_check") == ["ok"],
                  try strings(connection, "PRAGMA cipher_integrity_check").isEmpty else {
                throw Self.error("Verify durable encrypted database")
            }
        }
        let closeStatus = locus_sqlite3_close(source)
        guard closeStatus == LOCUS_SQLITE_OK else { throw Self.error("Close plaintext database", closeStatus) }
        sourceOpen = false
        try Self.protectFiles(at: candidate)
        // Source is fully checkpointed; stale sidecars must not reach the new inode.
        for suffix in ["-wal", "-shm", "-journal"] {
            let path = url.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }
        guard Darwin.rename(candidate.path, url.path) == 0 else {
            throw Self.error("Replace plaintext database", errno)
        }
        let directory = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY)
        guard directory >= 0 else { throw Self.error("Open database directory", errno) }
        defer {
            if Darwin.close(directory) != 0 {
                NSLog("[locus.SQLiteStorage] Directory close failed: %d", errno)
            }
        }
        guard fsync(directory) == 0 else { throw Self.error("Sync database directory", errno) }
        NSLog("[locus.SQLiteStorage] Plaintext database migrated to SQLCipher")
    }

    private func attach(_ url: URL, to connection: OpaquePointer) throws {
        try Self.createProtectedFile(at: url)
        var statement: OpaquePointer?
        let status = locus_sqlite3_prepare_v2(connection, "ATTACH DATABASE ? AS encrypted KEY ?", -1, &statement, nil)
        guard status == LOCUS_SQLITE_OK else { throw Self.error("Prepare encrypted export", status) }
        defer { locus_sqlite3_finalize(statement) }
        // Bind the key so errors and SQL traces cannot include it in SQL text.
        try url.path.withCString { path in
            try rawKey.withCString { key in
                let pathStatus = locus_sqlite3_bind_text(statement, 1, path, -1, nil)
                let keyStatus = locus_sqlite3_bind_text(statement, 2, key, -1, nil)
                guard pathStatus == LOCUS_SQLITE_OK, keyStatus == LOCUS_SQLITE_OK else {
                    throw Self.error("Bind encrypted export")
                }
                let result = locus_sqlite3_step(statement)
                guard result == LOCUS_SQLITE_DONE else { throw Self.error("Attach encrypted export", result) }
            }
        }
    }

    private func tableCounts(_ connection: OpaquePointer, schema: String = "main") throws -> [String: Int64] {
        let tables = try strings(connection, "SELECT name FROM \(schema).sqlite_master WHERE type='table'")
        var result: [String: Int64] = [:]
        for table in tables {
            let quoted = table.replacingOccurrences(of: "\"", with: "\"\"")
            result[table] = try integer(connection, "SELECT count(*) FROM \(schema).\"\(quoted)\"")
        }
        return result
    }

    private func integer(_ connection: OpaquePointer, _ sql: String) throws -> Int64 {
        guard let text = try strings(connection, sql).first, let value = Int64(text) else {
            throw Self.error("Read migration metadata")
        }
        return value
    }

    private func strings(_ connection: OpaquePointer, _ sql: String) throws -> [String] {
        var statement: OpaquePointer?
        let status = locus_sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard status == LOCUS_SQLITE_OK else { throw Self.error("Prepare migration query", status) }
        defer { locus_sqlite3_finalize(statement) }
        var result: [String] = []
        var step = locus_sqlite3_step(statement)
        while step == LOCUS_SQLITE_ROW {
            guard let value = locus_sqlite3_column_text(statement, 0) else {
                throw Self.error("Read migration query")
            }
            result.append(String(cString: value))
            step = locus_sqlite3_step(statement)
        }
        guard step == LOCUS_SQLITE_DONE else { throw Self.error("Run migration query", step) }
        return result
    }

    private func execute(_ connection: OpaquePointer, _ sql: String, operation: String) throws {
        let status = locus_sqlite3_exec(connection, sql, nil, nil, nil)
        guard status == LOCUS_SQLITE_OK else { throw Self.error(operation, status) }
    }

    private static func close(_ connection: OpaquePointer) {
        let status = locus_sqlite3_close(connection)
        if status != LOCUS_SQLITE_OK {
            NSLog("[locus.SQLiteStorage] Encryption connection close failed: %d", status)
        }
    }

    private static func error(_ operation: String, _ status: Int32 = LOCUS_SQLITE_ERROR) -> NSError {
        NSError(domain: "dev.locus.storage", code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "\(operation) failed (code \(status))"
        ])
    }

    private static func protectFiles(at url: URL) throws {
        #if os(iOS)
        for suffix in ["", "-wal", "-shm", "-journal"] {
            var file = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: file.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try file.setResourceValues(values)
        }
        #endif
    }

    private static func createProtectedFile(at url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attributes) else {
            throw Self.error("Create protected database")
        }
        try protectFiles(at: url)
    }
}

private final class DatabaseFileLock {
    private let descriptor: Int32

    init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        do { try shared() } catch {
            if Darwin.close(descriptor) != 0 {
                NSLog("[locus.SQLiteStorage] Lock close failed: %d", errno)
            }
            throw error
        }
    }

    deinit {
        if Darwin.close(descriptor) != 0 {
            NSLog("[locus.SQLiteStorage] Lock close failed: %d", errno)
        }
    }

    func shared() throws { try acquire(LOCK_SH) }
    func exclusive() throws { try acquire(LOCK_EX) }

    private func acquire(_ mode: Int32) throws {
        guard flock(descriptor, mode | LOCK_NB) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Database is in use; encryption will be retried"
            ])
        }
    }
}
