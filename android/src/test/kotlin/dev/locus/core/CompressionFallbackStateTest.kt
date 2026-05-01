package dev.locus.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the 415-fallback contract: a one-hour suppression window blocks
 * gzipping while a misbehaving proxy is live, then auto-clears so the
 * next batch tries compression again. The persistence half of the
 * contract is exercised through an injected in-memory store that mimics
 * what the real `ConfigManager` wires onto `SharedPreferences`.
 */
class CompressionFallbackStateTest {

    private class FakeClock(var nowMs: Long = 1_000_000_000L) : () -> Long {
        override fun invoke(): Long = nowMs
    }

    /**
     * Stand-in for the `SharedPreferences`-backed closures the production
     * `ConfigManager` injects. Tracks every save call so tests can pin
     * write amplification (the early-return path must not hit disk).
     */
    private class InMemoryStore {
        var deadlineMs: Long? = null
        var saveCount: Int = 0
            private set

        fun load(): Long? = deadlineMs

        fun save(value: Long?) {
            deadlineMs = value
            saveCount += 1
        }
    }

    private fun makeStateWithStore(
        clock: FakeClock = FakeClock(),
        store: InMemoryStore = InMemoryStore(),
    ): Triple<CompressionFallbackState, FakeClock, InMemoryStore> {
        val state = CompressionFallbackState(
            clock = clock,
            loadDeadline = { store.load() },
            saveDeadline = { store.save(it) },
        )
        return Triple(state, clock, store)
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

    // ----- Persistence -----

    @Test
    fun `hydrates from persisted future deadline`() {
        val clock = FakeClock()
        val store = InMemoryStore()
        // Direct field assignment seeds the value without going through
        // save(), so saveCount stays at 0 and pins the "init must not
        // write back to disk on hydration" contract below.
        store.deadlineMs = clock.nowMs + 30 * 60_000

        val (state, _, _) = makeStateWithStore(clock = clock, store = store)

        assertTrue(state.isDisabled)
        assertEquals("init must not write back to disk on hydration", 0, store.saveCount)
    }

    @Test
    fun `ignores past persisted deadline on init`() {
        val clock = FakeClock()
        val store = InMemoryStore()
        store.deadlineMs = clock.nowMs - 5 * 60_000

        val (state, _, _) = makeStateWithStore(clock = clock, store = store)

        assertFalse(state.isDisabled)
        assertEquals(
            "stale past values are inert; lazy expiry handles cleanup elsewhere",
            0,
            store.saveCount,
        )
    }

    @Test
    fun `disableFor persists the deadline`() {
        val (state, clock, store) = makeStateWithStore()
        state.disableFor(60_000)

        assertEquals(clock.nowMs + 60_000, store.deadlineMs)
        assertEquals(1, store.saveCount)
    }

    @Test
    fun `lazy expiry read clears persisted deadline`() {
        val (state, clock, store) = makeStateWithStore()
        state.disableFor(60_000)
        assertEquals(1, store.saveCount)

        clock.nowMs += 60_001
        assertFalse(state.isDisabled)
        assertNull(
            "expiry on read must clear disk in lockstep with memory",
            store.deadlineMs,
        )
        assertEquals(2, store.saveCount)
    }

    @Test
    fun `reset clears persisted deadline`() {
        val (state, _, store) = makeStateWithStore()
        state.disableFor(60_000)

        state.reset()

        assertNull(store.deadlineMs)
    }

    @Test
    fun `max-of survives across simulated restart`() {
        val clock = FakeClock()
        val store = InMemoryStore()
        val originalDeadline = clock.nowMs + 30 * 60_000
        store.deadlineMs = originalDeadline

        // First "process": just constructs and exits. Hydrates the deadline.
        CompressionFallbackState(
            clock = clock,
            loadDeadline = { store.load() },
            saveDeadline = { store.save(it) },
        )

        // Second "process": fresh instance, same store, hits 415 again with
        // a shorter window. The longer existing deadline must win and the
        // early-return must skip the disk write entirely.
        val secondState = CompressionFallbackState(
            clock = clock,
            loadDeadline = { store.load() },
            saveDeadline = { store.save(it) },
        )
        secondState.disableFor(60_000)

        assertEquals(
            "the longer existing deadline must survive the redundant disableFor",
            originalDeadline,
            store.deadlineMs,
        )
        assertEquals(
            "early-return path must not hit disk on a redundant 415 burst",
            0,
            store.saveCount,
        )
    }

    @Test
    fun `corrupt far-future persisted deadline is clamped on hydrate`() {
        val clock = FakeClock()
        val store = InMemoryStore()
        store.deadlineMs = clock.nowMs + 30L * 24 * 60 * 60 * 1000 // 30 days

        val (state, _, _) = makeStateWithStore(clock = clock, store = store)
        assertTrue(state.isDisabled)

        // Past the clamp ceiling but well before the corrupt 30-day deadline:
        // the in-memory deadline must have been clamped, so isDisabled flips
        // false and the (now-stale) on-disk value gets cleared by the lazy
        // expiry path on first read.
        clock.nowMs += CompressionFallbackState.MAX_FALLBACK_DURATION_MS + 1
        assertFalse(state.isDisabled)
    }
}
