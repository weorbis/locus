package dev.locus.core

/**
 * In-memory state machine for the Q8 §4.2 "415 → disable compression"
 * fallback. Extracted from [ConfigManager] so it has no Android Context
 * dependency — tests run as plain JVM JUnit, not under Robolectric.
 *
 * Thread-safe: a single intrinsic lock guards both reads and writes so a
 * concurrent disable from the response handler can't race the read on
 * the send path.
 */
internal class CompressionFallbackState(
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val lock = Any()
    private var disabledUntilMs: Long? = null

    /**
     * Disables compression for [durationMs] milliseconds from now.
     * Subsequent calls extend the deadline (max-of-existing-and-new) so
     * a back-to-back 415 burst doesn't shorten the window. Idempotent.
     */
    fun disableFor(durationMs: Long) {
        synchronized(lock) {
            val proposed = clock() + durationMs
            val existing = disabledUntilMs
            if (existing != null && existing > proposed) return
            disabledUntilMs = proposed
        }
    }

    /**
     * Whether compression is currently suppressed. Self-clears the
     * stored deadline on first read after expiry so callers don't keep
     * tripping the branch once the window closes.
     */
    val isDisabled: Boolean
        get() = synchronized(lock) {
            val until = disabledUntilMs ?: return@synchronized false
            if (clock() >= until) {
                disabledUntilMs = null
                return@synchronized false
            }
            true
        }

    /** Test-only seam: clears the flag regardless of the deadline. */
    fun reset() {
        synchronized(lock) {
            disabledUntilMs = null
        }
    }
}
