import XCTest
@testable import locus

/// Pins the Q8 §4.2 fallback contract: a one-hour suppression window
/// blocks gzipping while a misbehaving proxy is live, then auto-clears
/// so the next batch tries compression again.
///
/// Plain XCTest; no Flutter framework dependency. The state machine
/// accepts an injected clock, so deadline-based assertions don't depend
/// on wall clock advancement.
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

    private func makeState(
        clock: FakeClock = FakeClock()
    ) -> (CompressionFallbackState, FakeClock) {
        let state = CompressionFallbackState(clock: { clock.now })
        return (state, clock)
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
}
