import XCTest
#if canImport(Locus)
@testable import Locus
#elseif canImport(locus)
@testable import locus
#endif

final class SyncManagerRequestBuildFailureTests: XCTestCase {
    private static let databaseKey = Data("locus-native-storage-fixture-key".utf8)

    private final class InMemoryConfigStore: ConfigSnapshotStoring {
        func read() -> PersistedConfigSnapshot { .absent }

        func write(_ values: [String: Any]) throws {
            guard JSONSerialization.isValidJSONObject(values) else {
                throw ConfigSnapshotError.invalidJSON
            }
        }
    }

    private final class Delegate: SyncManagerDelegate {
        var requestBuildFailureCount = 0
        var nextFailureExpectation: XCTestExpectation?

        func buildSyncBody(
            locations: [[String: Any]],
            extras: [String: Any],
            completion: @escaping ([String: Any]?) -> Void
        ) {
            completion(nil)
        }

        func onPreSyncValidation(
            locations: [[String: Any]],
            extras: [String: Any],
            completion: @escaping (Bool) -> Void
        ) {
            completion(true)
        }

        func onHeadersRefresh(completion: @escaping ([String: String]?) -> Void) {
            completion(nil)
        }

        func onHttpEvent(_ event: [String: Any]) {
            guard
                let data = event["data"] as? [String: Any],
                data["responseText"] as? String == "request_build_failed"
            else {
                return
            }
            requestBuildFailureCount += 1
            nextFailureExpectation?.fulfill()
            nextFailureExpectation = nil
        }

        func onSyncEvent(_ event: [String: Any]) {}
        func onLog(level: String, message: String) {}
    }

    func testBatchRequestBuildFailureCompletesDrainForAnotherAttempt() throws {
        let storage = try makeStorage()
        let config = try makeConfig()
        config.httpUrl = "http://["
        config.maxBatchSize = 10
        config.maxRetry = 1
        config.retryDelay = 60

        let inserted = expectation(description: "location inserted")
        storage.saveLocation(Self.routePayload(), maxDays: 0, maxRecords: 0) {
            inserted.fulfill()
        }
        wait(for: [inserted], timeout: 2)

        let manager = SyncManager(config: config, storage: storage)
        let delegate = Delegate()
        manager.delegate = delegate

        let firstFailure = expectation(description: "first request build failure")
        delegate.nextFailureExpectation = firstFailure
        manager.syncStoredLocations(limit: 10)
        wait(for: [firstFailure], timeout: 2)

        let secondFailure = expectation(description: "second request build failure")
        delegate.nextFailureExpectation = secondFailure
        manager.syncStoredLocations(limit: 10)
        wait(for: [secondFailure], timeout: 2)

        XCTAssertEqual(delegate.requestBuildFailureCount, 2)
    }

    func testSingleRequestBuildFailureEmitsFailureEvent() throws {
        let storage = try makeStorage()
        let config = try makeConfig()
        config.httpUrl = "http://["
        config.maxRetry = 1
        config.retryDelay = 60

        let manager = SyncManager(config: config, storage: storage)
        let delegate = Delegate()
        manager.delegate = delegate

        let failure = expectation(description: "single request build failure")
        delegate.nextFailureExpectation = failure
        manager.syncNow(currentPayload: Self.routePayload())
        wait(for: [failure], timeout: 2)

        XCTAssertEqual(delegate.requestBuildFailureCount, 1)
    }

    private static func routePayload() -> [String: Any] {
        [
            "uuid": "request-build-failure-\(UUID().uuidString)",
            "timestamp": "2026-03-13T10:15:00.000Z",
            "coords": [
                "latitude": 27.25331,
                "longitude": 33.83411,
                "accuracy": 5,
            ],
            "extras": [
                "owner_id": "owner-a",
                "driver_id": "driver-a",
                "task_id": "task-a",
                "tracking_session_id": "session-a",
                "started_at": "2026-03-13T10:00:00.000Z",
            ],
        ]
    }

    private func makeStorage() throws -> StorageManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("locus-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "dev.locus.sync-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        return StorageManager(
            sqliteStorage: SQLiteStorage(
                databaseURL: directory.appendingPathComponent("storage.sqlite"),
                userDefaults: defaults,
                keyProvider: { Self.databaseKey }
            )
        )
    }

    private func makeConfig() throws -> ConfigManager {
        let suiteName = "dev.locus.sync-config-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return ConfigManager(
            snapshotStore: InMemoryConfigStore(),
            userDefaults: defaults
        )
    }
}
