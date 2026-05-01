package dev.locus.core

import kotlin.math.min

/**
 * State for the "415 → disable compression" fallback. The deadline is held
 * in memory for hot-path reads and mirrored to a caller-supplied store so
 * the suppression window survives process death (mobile processes get
 * killed often — Doze, OOM, foreground-service restart, force-stop, OS
 * upgrade, reboot). Without persistence every cold start inside the
 * window re-probes gzip and trips the same proxy again.
 *
 * Thread-safe: a single intrinsic lock guards both reads and writes so a
 * concurrent disable from the response handler can't race the read on
 * the send path.
 */
internal class CompressionFallbackState(
    private val clock: () -> Long = System::currentTimeMillis,
    loadDeadline: () -> Long? = { null },
    private val saveDeadline: (Long?) -> Unit = { },
) {
    companion object {
        /**
         * Upper bound applied to a hydrated deadline. Defends against a
         * corrupt or far-future value in the persistent store keeping
         * gzip suppressed indefinitely.
         */
        const val MAX_FALLBACK_DURATION_MS = 7_200_000L
    }

    private val lock = Any()
    private var disabledUntilMs: Long? = null

    init {
        // Hydrate once. Past or absent → no-op (the next isDisabled read
        // will lazy-clear stale disk state, so init stays write-free).
        val loaded = loadDeadline()
        if (loaded != null) {
            val now = clock()
            val ceiling = now + MAX_FALLBACK_DURATION_MS
            val clamped = min(loaded, ceiling)
            if (clamped > now) {
                disabledUntilMs = clamped
            }
        }
    }

    /**
     * Disables compression for [durationMs] milliseconds from now.
     * Subsequent calls extend the deadline (max-of-existing-and-new) so
     * a back-to-back 415 burst doesn't shorten the window. Idempotent.
     * Persists the new deadline; the early-return path skips the write
     * to keep a 415 burst from hammering disk.
     */
    fun disableFor(durationMs: Long) {
        synchronized(lock) {
            val proposed = clock() + durationMs
            val existing = disabledUntilMs
            if (existing != null && existing > proposed) return
            disabledUntilMs = proposed
            saveDeadline(proposed)
        }
    }

    /**
     * Whether compression is currently suppressed. Self-clears the
     * stored deadline on first read after expiry so callers don't keep
     * tripping the branch once the window closes; the persistent store
     * is cleared in lockstep.
     */
    val isDisabled: Boolean
        get() = synchronized(lock) {
            val until = disabledUntilMs ?: return@synchronized false
            if (clock() >= until) {
                disabledUntilMs = null
                saveDeadline(null)
                return@synchronized false
            }
            true
        }

    /** Test-only seam: clears the flag regardless of the deadline. */
    fun reset() {
        synchronized(lock) {
            disabledUntilMs = null
            saveDeadline(null)
        }
    }
}
