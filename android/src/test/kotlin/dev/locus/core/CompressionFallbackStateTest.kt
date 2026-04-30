package dev.locus.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the Q8 §4.2 fallback contract: a one-hour suppression window
 * blocks gzipping while a misbehaving proxy is live, then auto-clears so
 * the next batch tries compression again.
 *
 * Plain JUnit; no Android dependencies. The state machine accepts an
 * injected clock, so deadline-based assertions don't depend on wall
 * clock advancement.
 */
class CompressionFallbackStateTest {

    private class FakeClock(var nowMs: Long = 1_000_000_000L) : () -> Long {
        override fun invoke(): Long = nowMs
    }

    @Test
    fun `disabled is false by default`() {
        val state = CompressionFallbackState()
        assertFalse(state.isDisabled)
    }

    @Test
    fun `disableFor sets the flag for the duration window`() {
        val clock = FakeClock()
        val state = CompressionFallbackState(clock = clock)

        state.disableFor(60_000) // 60 seconds
        assertTrue(state.isDisabled)
    }

    @Test
    fun `flag clears on read after the deadline elapses`() {
        val clock = FakeClock()
        val state = CompressionFallbackState(clock = clock)

        state.disableFor(60_000)
        assertTrue(state.isDisabled)

        // Jump past the deadline.
        clock.nowMs += 60_001
        assertFalse(state.isDisabled)
    }

    @Test
    fun `back-to-back disables extend the window, never shorten it`() {
        val clock = FakeClock()
        val state = CompressionFallbackState(clock = clock)

        state.disableFor(10 * 60_000) // 10-minute window first
        state.disableFor(60_000) // then a 1-minute window — must not shrink

        // Still disabled at 9 minutes (only the 1-minute window would have
        // elapsed; the longer 10-minute one still applies).
        clock.nowMs += 9 * 60_000
        assertTrue(state.isDisabled)
    }

    @Test
    fun `extending with a longer window pushes the deadline out`() {
        val clock = FakeClock()
        val state = CompressionFallbackState(clock = clock)

        state.disableFor(60_000) // 1-minute window
        // Then a 30-minute window — must extend, not be ignored.
        state.disableFor(30 * 60_000)

        // 5 minutes in: original 1-minute window has expired, but the
        // extended 30-minute window keeps the flag asserted.
        clock.nowMs += 5 * 60_000
        assertTrue(state.isDisabled)
    }

    @Test
    fun `reset clears the flag immediately`() {
        val clock = FakeClock()
        val state = CompressionFallbackState(clock = clock)

        state.disableFor(60_000)
        assertTrue(state.isDisabled)

        state.reset()
        assertFalse(state.isDisabled)
    }
}
