import XCTest
#if canImport(Locus)
@testable import Locus
#elseif canImport(locus)
@testable import locus
#endif

final class SQLiteStorageMigrationTests: XCTestCase {
    private static let databaseKey = Data("locus-native-storage-fixture-key".utf8)

    func testLegacyRowsAreRemovedOnlyAfterTransactionCommits() throws {
        let fixture = try makeFixture()
        fixture.defaults.set(
            [["uuid": "location-1", "timestamp": "2026-07-13T10:00:00Z"]],
            forKey: "bg_locations"
        )
        fixture.defaults.set(
            [["identifier": "office", "latitude": 52.0, "longitude": 4.0, "radius": 100.0]],
            forKey: "bg_geofences"
        )

        let storage = SQLiteStorage(
            databaseURL: fixture.databaseURL,
            userDefaults: fixture.defaults,
            keyProvider: { Self.databaseKey }
        )

        XCTAssertEqual(storage.readLocations().count, 1)
        XCTAssertEqual(storage.readGeofences().count, 1)
        XCTAssertNil(fixture.defaults.object(forKey: "bg_locations"))
        XCTAssertNil(fixture.defaults.object(forKey: "bg_geofences"))
        XCTAssertTrue(fixture.defaults.bool(forKey: "locus_sqlite_migrated"))
    }

    func testAnyFailedInsertRollsBackAndPreservesEveryLegacySource() throws {
        let fixture = try makeFixture()
        let locations = [["uuid": "location-1", "timestamp": "2026-07-13T10:00:00Z"]]
        let invalidGeofences = [["latitude": 52.0, "longitude": 4.0, "radius": 100.0]]
        fixture.defaults.set(locations, forKey: "bg_locations")
        fixture.defaults.set(invalidGeofences, forKey: "bg_geofences")

        let storage = SQLiteStorage(
            databaseURL: fixture.databaseURL,
            userDefaults: fixture.defaults,
            keyProvider: { Self.databaseKey }
        )

        XCTAssertTrue(storage.readLocations().isEmpty)
        XCTAssertNotNil(fixture.defaults.array(forKey: "bg_locations"))
        XCTAssertNotNil(fixture.defaults.array(forKey: "bg_geofences"))
        XCTAssertFalse(fixture.defaults.bool(forKey: "locus_sqlite_migrated"))
    }

    func testCommittedReceiptPreventsDuplicateLogsAfterCleanupCrashWindow() throws {
        let fixture = try makeFixture()
        let legacyLog = "1710000000|info|started"
        fixture.defaults.set(legacyLog, forKey: "bg_log")

        do {
            let storage = SQLiteStorage(
                databaseURL: fixture.databaseURL,
                userDefaults: fixture.defaults,
                keyProvider: { Self.databaseKey }
            )
            XCTAssertEqual(storage.readLogs().count, 1)
        }

        // Simulate a process dying after SQLite commit but before legacy source
        // cleanup became durable.
        fixture.defaults.set(false, forKey: "locus_sqlite_migrated")
        fixture.defaults.set(legacyLog, forKey: "bg_log")

        let restarted = SQLiteStorage(
            databaseURL: fixture.databaseURL,
            userDefaults: fixture.defaults,
            keyProvider: { Self.databaseKey }
        )

        XCTAssertEqual(restarted.readLogs().count, 1)
        XCTAssertNil(fixture.defaults.object(forKey: "bg_log"))
        XCTAssertTrue(fixture.defaults.bool(forKey: "locus_sqlite_migrated"))
    }

    func testMalformedLogDoesNotBlockValidLocationMigration() throws {
        let fixture = try makeFixture()
        fixture.defaults.set(
            [["uuid": "location-1", "timestamp": "2026-07-13T10:00:00Z"]],
            forKey: "bg_locations"
        )
        fixture.defaults.set("not-a-valid-log-row", forKey: "bg_log")

        let storage = SQLiteStorage(
            databaseURL: fixture.databaseURL,
            userDefaults: fixture.defaults,
            keyProvider: { Self.databaseKey }
        )

        XCTAssertEqual(storage.readLocations().count, 1)
        XCTAssertTrue(storage.readLogs().isEmpty)
        XCTAssertNil(fixture.defaults.object(forKey: "bg_log"))
        XCTAssertTrue(fixture.defaults.bool(forKey: "locus_sqlite_migrated"))
    }

    func testReleasedDocumentsDatabasePathRemainsCanonical() {
        let documents = URL(fileURLWithPath: "/documents", isDirectory: true)

        XCTAssertEqual(
            SQLiteStorage.databaseURL(
                documentsDirectory: documents
            ),
            documents.appendingPathComponent("locus_storage.sqlite")
        )
    }

    func testMissingDocumentsPathDoesNotCreateASecondDatabase() {
        XCTAssertNil(
            SQLiteStorage.databaseURL(documentsDirectory: nil),
            "a temporary fallback would hide live data when Documents returns"
        )
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("locus-migration-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "dev.locus.migration-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        return Fixture(
            databaseURL: directory.appendingPathComponent("storage.sqlite"),
            defaults: defaults
        )
    }

    private struct Fixture {
        let databaseURL: URL
        let defaults: UserDefaults
    }
}
