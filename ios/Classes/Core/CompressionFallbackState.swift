import Foundation

/// State for the "415 → disable compression" fallback. The deadline is held
/// in memory for hot-path reads and mirrored to a caller-supplied store so
/// the suppression window survives process death (mobile processes get
/// killed often — Doze, OOM, foreground-service restart, force-stop, OS
/// upgrade, reboot, iOS background-launch). Without persistence every cold
/// start inside the window re-probes gzip and trips the same proxy again.
///
/// Thread-safe: a single dispatch queue serialises reads and writes so a
/// concurrent disable from the response handler can't race the read on
/// the send path.
final class CompressionFallbackState {
    /// Upper bound applied to a hydrated deadline. Defends against a
    /// corrupt or far-future value in the persistent store keeping gzip
    /// suppressed indefinitely.
    static let maxFallbackDurationSeconds: TimeInterval = 7200

    private let queue: DispatchQueue
    private let clock: () -> Date
    private let saveDeadline: (Date?) -> Void
    private var disabledUntil: Date?

    init(
        clock: @escaping () -> Date = Date.init,
        loadDeadline: () -> Date? = { nil },
        saveDeadline: @escaping (Date?) -> Void = { _ in },
        queueLabel: String = "dev.locus.config.compressionfallback"
    ) {
        self.clock = clock
        self.saveDeadline = saveDeadline
        self.queue = DispatchQueue(label: queueLabel)

        // Hydrate once. Past or absent → no-op (the next isDisabled read
        // will lazy-clear stale disk state, so init stays write-free).
        if let loaded = loadDeadline() {
            let now = clock()
            let ceiling = now.addingTimeInterval(
                CompressionFallbackState.maxFallbackDurationSeconds
            )
            let clamped = min(loaded, ceiling)
            if clamped > now {
                disabledUntil = clamped
            }
        }
    }

    /// Disables compression for `duration` seconds from now. Subsequent
    /// calls extend the deadline (max-of-existing-and-new) so a
    /// back-to-back 415 burst doesn't shorten the window. Idempotent.
    /// Persists the new deadline; the early-return path skips the write
    /// to keep a 415 burst from hammering disk.
    func disableFor(duration: TimeInterval) {
        queue.sync {
            let proposed = clock().addingTimeInterval(duration)
            if let existing = disabledUntil, existing > proposed {
                return
            }
            disabledUntil = proposed
            saveDeadline(proposed)
        }
    }

    /// Whether compression is currently suppressed. Self-clears the
    /// stored deadline on first read after expiry so callers don't keep
    /// tripping the branch once the window closes; the persistent store
    /// is cleared in lockstep.
    var isDisabled: Bool {
        queue.sync {
            guard let until = disabledUntil else { return false }
            if clock() >= until {
                disabledUntil = nil
                saveDeadline(nil)
                return false
            }
            return true
        }
    }

    /// Test-only seam: clears the flag regardless of the deadline.
    func reset() {
        queue.sync {
            disabledUntil = nil
            saveDeadline(nil)
        }
    }
}
