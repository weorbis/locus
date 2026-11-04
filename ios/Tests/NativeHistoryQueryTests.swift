import Foundation
import XCTest
#if canImport(Locus)
@testable import Locus
#elseif canImport(locus)
@testable import locus
#endif

final class NativeHistoryQueryTests: XCTestCase {
    private let epoch: Int64 = 1_783_936_800_000_000

    func testEveryFilterRunsBeforePagingInBothSortOrders() async throws {
        let fixture = try makeFixture()
        for second in [0, 8] {
            fixture.storage.insertLocation(location("inaccurate-\(second)", second: second, accuracy: 101))
            fixture.storage.insertLocation(location("too-accurate-\(second)", second: second, accuracy: 9))
            fixture.storage.insertLocation(location("stationary-\(second)", second: second, moving: false))
            fixture.storage.insertLocation(location("outside-\(second)", second: second, latitude: 60))
        }
        fixture.storage.insertLocation(location("before", second: -1))
        fixture.storage.insertLocation(location("after", second: 9))
        for second in [2, 3, 4] {
            fixture.storage.insertLocation(location("match-\(second)", second: second))
        }
        let filters: [String: Any] = [
            "from": epoch, "to": epoch + 8_000_000,
            "minAccuracy": 100, "maxAccuracy": 10, "isMoving": true,
            "bounds": bounds(south: 51, west: 3, north: 53, east: 5),
            "limit": 2, "offset": 1,
        ]
        for sortOrder in ["oldestFirst", "newestFirst"] {
            var arguments = filters
            arguments["sortOrder"] = sortOrder
            let rows = try await query(fixture.storage, arguments)
            let expected = sortOrder == "oldestFirst" ? ["match-3", "match-4"] : ["match-3", "match-2"]
            XCTAssertEqual(ids(rows), expected, sortOrder)
        }
        XCTAssertEqual(fixture.storage.locationCount(), 13)
    }

    func testBoundsAndAccuracyEdgesAreInclusive() async throws {
        let fixture = try makeFixture()
        fixture.storage.insertLocation(location("southwest", accuracy: 10, latitude: 51, longitude: 3))
        fixture.storage.insertLocation(location("northeast", accuracy: 100, latitude: 53, longitude: 5))
        fixture.storage.insertLocation(location("outside", latitude: 53.000001))
        let rows = try await query(fixture.storage, [
            "minAccuracy": 100, "maxAccuracy": 10,
            "bounds": bounds(south: 51, west: 3, north: 53, east: 5),
        ])
        XCTAssertEqual(ids(rows), ["southwest", "northeast"])
    }

    func testMicrosecondBoundariesAndTimezoneOffsetsAreInclusive() async throws {
        let fixture = try makeFixture()
        for (id, timestamp) in [
            ("before", "2026-07-13T10:00:00.123455Z"),
            ("edge", "2026-07-13T12:00:00.123456+02:00"),
            ("after", "2026-07-13T10:00:00.123457Z"),
        ] {
            fixture.storage.insertLocation(location(id, timestamp: timestamp))
        }
        let edge = epoch + 123_456
        let rows = try await query(fixture.storage, ["from": edge, "to": edge])
        XCTAssertEqual(ids(rows), ["edge"])
    }

    func testNegativeEpochFractionsSortChronologically() async throws {
        let fixture = try makeFixture()
        fixture.storage.insertLocation(location("earlier", timestamp: "1969-12-31T23:59:59.999998Z"))
        fixture.storage.insertLocation(location("edge", timestamp: "1969-12-31T23:59:59.999999Z"))
        fixture.storage.insertLocation(location("epoch", timestamp: "1970-01-01T00:00:00Z"))
        let rows = try await query(fixture.storage, ["from": Int64(-1), "to": Int64(-1)])
        XCTAssertEqual(ids(rows), ["edge"])
        let sorted = try await query(fixture.storage, ["sortOrder": "oldestFirst"])
        XCTAssertEqual(ids(sorted), ["earlier", "edge", "epoch"])
    }

    func testTiedTimestampsKeepInsertionOrderAcrossPagesAndSortDirections() async throws {
        let fixture = try makeFixture()
        for id in ["z", "a", "m"] {
            fixture.storage.insertLocation(location(id))
        }
        for sortOrder in ["oldestFirst", "newestFirst"] {
            let first = try await query(fixture.storage, ["sortOrder": sortOrder, "limit": 2])
            let second = try await query(fixture.storage, ["sortOrder": sortOrder, "limit": 2, "offset": 2])
            XCTAssertEqual(ids(first) + ids(second), ["z", "a", "m"], sortOrder)
        }
    }

    func testNonpositiveLimitsAreEmptyAndNegativeOffsetStartsAtFirstMatch() async throws {
        let fixture = try makeFixture()
        fixture.storage.insertLocation(location("first"))
        fixture.storage.insertLocation(location("second", second: 1))
        for limit in [0, -1] {
            let rows = try await query(fixture.storage, ["limit": limit])
            XCTAssertTrue(rows.isEmpty)
        }
        let rows = try await query(fixture.storage, ["offset": -10, "limit": 1, "sortOrder": "oldestFirst"])
        XCTAssertEqual(ids(rows), ["first"])
    }

    func testOmittedLimitReturnsAllMatchesWithoutChangingLegacyReadsOrCount() async throws {
        let fixture = try makeFixture()
        let recordCount = 120
        for index in 0 ..< recordCount {
            fixture.storage.insertLocation(location("row-\(index)", moving: index.isMultiple(of: 2)))
        }
        let before = fixture.storage.readLocations()
        let rows = try await query(fixture.storage, ["isMoving": true])
        XCTAssertEqual(rows.count, recordCount / 2)
        let allRows = try await query(fixture.storage)
        XCTAssertEqual(allRows.count, recordCount)
        XCTAssertEqual(fixture.storage.locationCount(), recordCount)
        XCTAssertEqual(fixture.storage.readLocations() as NSArray, before as NSArray)
        XCTAssertEqual(fixture.storage.readLocations(limit: 3).count, 3)
    }

    func testMissingNullAndInvalidTimestampsUseTheCapturedFallback() async throws {
        let fixture = try makeFixture()
        var missing = location("missing")
        missing.removeValue(forKey: "timestamp")
        var null = location("null")
        null["timestamp"] = NSNull()
        for row in [missing, null, location("invalid", timestamp: "not-a-date")] {
            fixture.storage.insertLocation(row)
        }
        let fallback: Int64 = 42
        let rows = try await query(fixture.storage, ["from": fallback, "to": fallback])
        XCTAssertEqual(ids(rows), ["missing", "null", "invalid"])
    }

    func testInvalidCoordinatesUseTheExistingZeroCoordinateAndNegativeAccuracyFallback() async throws {
        let fixture = try makeFixture()
        fixture.storage.insertLocation(location("invalid", accuracy: 50, latitude: 91, longitude: 4))
        fixture.storage.insertLocation(location("valid"))
        let rows = try await query(fixture.storage, [
            "minAccuracy": -1, "maxAccuracy": -1,
            "bounds": bounds(south: 0, west: 0, north: 0, east: 0),
        ])
        XCTAssertEqual(ids(rows), ["invalid"])
    }

    func testMissingAndNullCoordinateFieldsUseZeroDefaults() async throws {
        let fixture = try makeFixture()
        var missing = location("missing")
        missing.removeValue(forKey: "coords")
        var null = location("null")
        null["coords"] = ["latitude": NSNull(), "longitude": NSNull(), "accuracy": NSNull()]
        fixture.storage.insertLocation(missing)
        fixture.storage.insertLocation(null)
        fixture.storage.insertLocation(location("ordinary"))
        let rows = try await query(fixture.storage, [
            "minAccuracy": 0, "maxAccuracy": 0,
            "bounds": bounds(south: 0, west: 0, north: 0, east: 0),
        ])
        XCTAssertEqual(ids(rows), ["missing", "null"])
    }

    func testMalformedArgumentsAreRejectedInsteadOfReturningAnEmptyPage() {
        let malformed: [Any] = [
            NSNull(), [:], ["timestampFallback": true],
            ["timestampFallback": 42, "limit": 1.5],
            ["timestampFallback": 42, "from": "42"],
            ["timestampFallback": 42, "offset": true],
            ["timestampFallback": 42, "sortOrder": "sideways"],
            ["timestampFallback": 42, "isMoving": 1],
            ["timestampFallback": 42, "bounds": ["southwest": ["latitude": 0]]],
        ]
        for arguments in malformed {
            XCTAssertThrowsError(try StoredLocationQuery(arguments: arguments)) { error in
                XCTAssertEqual((error as NSError).domain, "dev.locus.locationQuery")
            }
        }
    }

    func testMalformedStoredValuesAreSkippedWithoutFailingTheQuery() async throws {
        for field in ["timestamp", "latitude", "accuracy", "is_moving"] {
            let fixture = try makeFixture()
            var row = location("malformed")
            if field == "latitude" || field == "accuracy" {
                var coords = try XCTUnwrap(row["coords"] as? [String: Any])
                coords[field] = "invalid-number"
                row["coords"] = coords
            } else {
                row[field] = field == "timestamp" ? 123 : "true"
            }
            fixture.storage.insertLocation(row)
            fixture.storage.insertLocation(location("valid", second: 1))
            let rows = try await query(fixture.storage, ["isMoving": true])
            XCTAssertEqual(ids(rows), ["valid"], field)
            XCTAssertEqual(fixture.storage.locationCount(), 2)
        }
    }

    func testQueryCompletesWhenItsQueueOwnsTheLastStorageReference() async throws {
        var fixture: Fixture? = try makeFixture(retainUntilTeardown: false)
        weak var releasedStorage: SQLiteStorage?
        func storageQueue(_ label: String) throws -> DispatchQueue {
            try XCTUnwrap(
                try Mirror(reflecting: XCTUnwrap(fixture).storage).children
                    .first { $0.label == label }?.value as? DispatchQueue
            )
        }
        let queue = try storageQueue("queue")
        let queryQueue = try storageQueue("queryQueue")
        releasedStorage = fixture?.storage
        let blocker = DispatchSemaphore(value: 0)
        queryQueue.async {
            XCTAssertEqual(blocker.wait(timeout: .now() + 5), .success)
        }
        let completed = expectation(description: "Query completes after its caller releases storage")
        let query = try StoredLocationQuery(arguments: ["timestampFallback": Int64(42)])
        try XCTUnwrap(fixture).storage.queryLocations(query) { result in
            XCTAssertTrue(Thread.isMainThread)
            switch result {
            case let .success(rows):
                XCTAssertTrue(rows.isEmpty)
            case let .failure(error):
                XCTFail(error.localizedDescription)
            }
            completed.fulfill()
        }
        // The blocked query queue now owns the only strong reference through the
        // pending query. Releasing that query must safely close on this queue.
        fixture = nil
        blocker.signal()
        await fulfillment(of: [completed], timeout: 5)
        queryQueue.sync {}
        queue.sync {}
        XCTAssertNil(releasedStorage)
    }

    func testProlepticGregorianYear1500UsesExactUtcEpoch() async throws {
        // Python datetime's proleptic Gregorian arithmetic, not Foundation's
        // historical Gregorian cutover: 470 * 365 days plus Gregorian leap days.
        try await assertTimestamp("1500-01-01T00:00:00Z", equals: -14_831_769_600_000_000)
    }

    func testLargeNumericTimezoneOffsetIsAccepted() async throws {
        try await assertTimestamp("2026-01-01T19:00:00+19", equals: 1_767_225_600_000_000)
    }

    func testOverflowDayNormalizesLikeDartDateTimeParse() async throws {
        try await assertTimestamp("2020-01-42T00:00:00Z", equals: 1_581_379_200_000_000)
    }

    func testSuffixlessHistoricalTimestampUsesDartEquivalentYearOffset() async throws {
        let restoreTimeZone = useSystemTimeZone("Europe/Amsterdam")
        defer { restoreTimeZone() }
        // Dart uses the equivalent modern year's +01:00 offset, not the
        // historical Amsterdam local mean time recorded in the zone database.
        try await assertTimestamp("1500-01-01T00:00:00", equals: -14_831_773_200_000_000)
    }

    func testSuffixlessDstGapAndOverlapMatchDartInstantSelection() async throws {
        let restoreTimeZone = useSystemTimeZone("Europe/Amsterdam")
        defer { restoreTimeZone() }
        try await assertTimestamp("2026-03-29T02:30:00", equals: 1_774_747_800_000_000)
        try await assertTimestamp("2026-10-25T02:30:00", equals: 1_792_888_200_000_000)
    }

    // Dart reads the system zone, so the test sets TZ rather than NSTimeZone.default.
    private func useSystemTimeZone(_ identifier: String) -> () -> Void {
        let original = getenv("TZ").map { String(cString: $0) }
        setenv("TZ", identifier, 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        return {
            if let original { setenv("TZ", original, 1) } else { unsetenv("TZ") }
            tzset()
            NSTimeZone.resetSystemTimeZone()
        }
    }

    private func assertTimestamp(_ timestamp: String, equals expected: Int64) async throws {
        let fixture = try makeFixture()
        fixture.storage.insertLocation(location("edge", timestamp: timestamp))
        let matching = try await query(fixture.storage, ["from": expected, "to": expected])
        XCTAssertEqual(ids(matching), ["edge"], timestamp)
        let before = try await query(fixture.storage, ["to": expected - 1])
        let after = try await query(fixture.storage, ["from": expected + 1])
        XCTAssertTrue(before.isEmpty, timestamp)
        XCTAssertTrue(after.isEmpty, timestamp)
    }

    private func query(_ storage: SQLiteStorage, _ arguments: [String: Any] = [:]) async throws -> [[String: Any]] {
        var arguments = arguments
        arguments["timestampFallback"] = Int64(42)
        let query = try StoredLocationQuery(arguments: arguments)
        return try await withCheckedThrowingContinuation { continuation in
            storage.queryLocations(query) { result in
                XCTAssertTrue(Thread.isMainThread, "Query completions must return to the channel's main thread")
                continuation.resume(with: result)
            }
        }
    }

    private func location(
        _ id: String,
        second: Int = 0,
        timestamp: String? = nil,
        accuracy: Double = 25,
        moving: Bool = true,
        latitude: Double = 52,
        longitude: Double = 4
    ) -> [String: Any] {
        let date = Date(timeIntervalSince1970: Double(epoch / 1_000_000) + Double(second))
        return [
            "uuid": id,
            "timestamp": timestamp ?? ISO8601DateFormatter().string(from: date),
            "coords": ["latitude": latitude, "longitude": longitude, "accuracy": accuracy],
            "is_moving": moving,
        ]
    }

    private func bounds(south: Double, west: Double, north: Double, east: Double) -> [String: Any] {
        [
            "southwest": ["latitude": south, "longitude": west],
            "northeast": ["latitude": north, "longitude": east],
        ]
    }

    private func ids(_ rows: [[String: Any]]) -> [String] {
        rows.map { $0["uuid"] as? String ?? "<missing uuid>" }
    }

    private func makeFixture(retainUntilTeardown: Bool = true) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("locus-history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "dev.locus.history-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let storage = SQLiteStorage(
            databaseURL: directory.appendingPathComponent("storage.sqlite"),
            userDefaults: defaults
        )
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        if retainUntilTeardown {
            addTeardownBlock {
                // Keep storage alive until its asynchronous work has drained,
                // and release it on the test runner rather than its serial queue.
                _ = storage.locationCount()
            }
        }
        return Fixture(storage: storage)
    }

    private struct Fixture {
        let storage: SQLiteStorage
    }
}
