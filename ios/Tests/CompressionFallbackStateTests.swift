import XCTest
@testable import Locus

/// Pins the 415-fallback contract: a one-hour suppression window blocks
/// gzipping while a misbehaving proxy is live, then auto-clears so the
/// next batch tries compression again. The persistence half of the
/// contract is exercised through an injected in-memory store that mimics
/// what the real `ConfigManager` wires onto `UserDefaults`.
final class CompressionFallbackStateTests: XCTestCase {
    private final class FakeClock {
        var now: Date

        init(_ start: Date = Date(timeIntervalSince1970: 1_000_000_000)) {
            self.now = start
        }

        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    /// Stand-in for the `UserDefaults`-backed closures the production
    /// `ConfigManager` injects. Tracks every save call so tests can pin
    /// write amplification (the early-return path must not hit disk).
    private final class InMemoryStore {
        var deadline: Date?
        private(set) var saveCount = 0

        func load() -> Date? { deadline }

        func save(_ value: Date?) {
            deadline = value
            saveCount += 1
        }
    }

    private func makeState(
        clock: FakeClock = FakeClock()
    ) -> (CompressionFallbackState, FakeClock) {
        let state = CompressionFallbackState(clock: { clock.now })
        return (state, clock)
    }

    private func makeStateWithStore(
        clock: FakeClock = FakeClock(),
        store: InMemoryStore = InMemoryStore()
    ) -> (CompressionFallbackState, FakeClock, InMemoryStore) {
        let state = CompressionFallbackState(
            clock: { clock.now },
            loadDeadline: { store.load() },
            saveDeadline: { store.save($0) }
        )
        return (state, clock, store)
    }

    func testDisabledIsFalseByDefault() {
        let (state, _) = makeState()
        XCTAssertFalse(state.isDisabled)
    }

    func testDisableForSetsTheFlagForTheDurationWindow() {
        let (state, _) = makeState()
        state.disableFor(duration: 60)
        XCTAssertTrue(state.isDisabled)
    }

    func testFlagClearsOnReadAfterTheDeadlineElapses() {
        let (state, clock) = makeState()
        state.disableFor(duration: 60)
        XCTAssertTrue(state.isDisabled)

        clock.advance(by: 61)
        XCTAssertFalse(state.isDisabled)
    }

    func testBackToBackDisablesExtendTheWindowAndNeverShortenIt() {
        let (state, clock) = makeState()
        state.disableFor(duration: 600) // 10-minute window first
        state.disableFor(duration: 60)  // then a 1-minute window

        // 9 minutes in: the 1-minute window would have elapsed long ago,
        // but the longer 10-minute window still applies.
        clock.advance(by: 9 * 60)
        XCTAssertTrue(state.isDisabled)
    }

    func testExtendingWithLongerWindowPushesTheDeadlineOut() {
        let (state, clock) = makeState()
        state.disableFor(duration: 60)        // 1-minute window
        state.disableFor(duration: 30 * 60)   // then a 30-minute window

        // 5 minutes in: the original 1-minute window has expired but the
        // extended 30-minute window keeps the flag asserted.
        clock.advance(by: 5 * 60)
        XCTAssertTrue(state.isDisabled)
    }

    func testResetClearsTheFlagImmediately() {
        let (state, _) = makeState()
        state.disableFor(duration: 60)
        XCTAssertTrue(state.isDisabled)

        state.reset()
        XCTAssertFalse(state.isDisabled)
    }

    // MARK: - Persistence

    func testHydratesFromPersistedFutureDeadline() {
        let clock = FakeClock()
        let store = InMemoryStore()
        // Direct field assignment seeds the value without going through
        // save(), so saveCount stays at 0 and the assertion below pins
        // "init must not write back to disk on hydration".
        store.deadline = clock.now.addingTimeInterval(30 * 60)

        let (state, _, _) = makeStateWithStore(clock: clock, store: store)

        XCTAssertTrue(state.isDisabled)
        XCTAssertEqual(store.saveCount, 0,
                       "init must not write back to disk on hydration")
    }

    func testIgnoresPastPersistedDeadlineOnInit() {
        let clock = FakeClock()
        let store = InMemoryStore()
        store.deadline = clock.now.addingTimeInterval(-5 * 60)

        let (state, _, _) = makeStateWithStore(clock: clock, store: store)

        XCTAssertFalse(state.isDisabled)
        XCTAssertEqual(store.saveCount, 0,
                       "stale past values are inert; lazy expiry handles cleanup elsewhere")
    }

    func testDisableForPersistsTheDeadline() {
        let (state, clock, store) = makeStateWithStore()
        state.disableFor(duration: 60)

        XCTAssertEqual(store.deadline, clock.now.addingTimeInterval(60))
        XCTAssertEqual(store.saveCount, 1)
    }

    func testLazyExpiryReadClearsPersistedDeadline() {
        let (state, clock, store) = makeStateWithStore()
        state.disableFor(duration: 60)
        XCTAssertEqual(store.saveCount, 1)

        clock.advance(by: 61)
        XCTAssertFalse(state.isDisabled)
        XCTAssertNil(store.deadline,
                     "expiry on read must clear disk in lockstep with memory")
        XCTAssertEqual(store.saveCount, 2)
    }

    func testResetClearsPersistedDeadline() {
        let (state, _, store) = makeStateWithStore()
        state.disableFor(duration: 60)

        state.reset()

        XCTAssertNil(store.deadline)
    }

    func testMaxOfSurvivesAcrossSimulatedRestart() {
        let clock = FakeClock()
        let store = InMemoryStore()
        let originalDeadline = clock.now.addingTimeInterval(30 * 60)
        store.deadline = originalDeadline

        // First "process": just constructs and exits. Hydrates the deadline.
        _ = CompressionFallbackState(
            clock: { clock.now },
            loadDeadline: { store.load() },
            saveDeadline: { store.save($0) }
        )

        // Second "process": fresh instance, same store, hits 415 again with
        // a shorter window. The longer existing deadline must win and the
        // early-return must skip the disk write entirely.
        let secondState = CompressionFallbackState(
            clock: { clock.now },
            loadDeadline: { store.load() },
            saveDeadline: { store.save($0) }
        )
        secondState.disableFor(duration: 60)

        XCTAssertEqual(store.deadline, originalDeadline,
                       "the longer existing deadline must survive the redundant disableFor")
        XCTAssertEqual(store.saveCount, 0,
                       "early-return path must not hit disk on a redundant 415 burst")
    }

    func testCorruptFarFuturePersistedDeadlineIsClampedOnHydrate() {
        let clock = FakeClock()
        let store = InMemoryStore()
        store.deadline = clock.now.addingTimeInterval(30 * 24 * 60 * 60) // 30 days

        let (state, _, _) = makeStateWithStore(clock: clock, store: store)
        XCTAssertTrue(state.isDisabled)

        // Past the clamp ceiling but well before the corrupt 30-day deadline:
        // the in-memory deadline must have been clamped, so isDisabled flips
        // false and the (now-stale) on-disk value gets cleared by the lazy
        // expiry path on first read.
        clock.advance(by: CompressionFallbackState.maxFallbackDurationSeconds + 1)
        XCTAssertFalse(state.isDisabled)
    }
}
