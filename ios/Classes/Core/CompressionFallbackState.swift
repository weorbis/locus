import Foundation

/// In-memory state machine for the Q8 §4.2 "415 → disable compression"
/// fallback. Extracted from `ConfigManager` so it has no plugin
/// dependencies — tests run as plain XCTest, no Flutter framework
/// required.
///
/// Thread-safe: a single dispatch queue serialises reads and writes so a
/// concurrent disable from the response handler can't race the read on
/// the send path.
final class CompressionFallbackState {
    private let queue: DispatchQueue
    private let clock: () -> Date
    private var disabledUntil: Date?

    init(
        clock: @escaping () -> Date = Date.init,
        queueLabel: String = "dev.locus.config.compressionfallback"
    ) {
        self.clock = clock
        self.queue = DispatchQueue(label: queueLabel)
    }

    /// Disables compression for `duration` seconds from now. Subsequent
    /// calls extend the deadline (max-of-existing-and-new) so a
    /// back-to-back 415 burst doesn't shorten the window. Idempotent.
    func disableFor(duration: TimeInterval) {
        queue.sync {
            let proposed = clock().addingTimeInterval(duration)
            if let existing = disabledUntil, existing > proposed {
                return
            }
            disabledUntil = proposed
        }
    }

    /// Whether compression is currently suppressed. Self-clears the
    /// stored deadline on first read after expiry so callers don't keep
    /// tripping the branch once the window closes.
    var isDisabled: Bool {
        queue.sync {
            guard let until = disabledUntil else { return false }
            if clock() >= until {
                disabledUntil = nil
                return false
            }
            return true
        }
    }

    /// Test-only seam: clears the flag regardless of the deadline.
    func reset() {
        queue.sync {
            disabledUntil = nil
        }
    }
}
