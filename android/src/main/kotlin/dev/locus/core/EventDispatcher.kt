package dev.locus.core

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

class EventDispatcher(
    private val headlessDispatcher: HeadlessDispatcher
) {
    private val mainHandler = Handler(Looper.getMainLooper())

    // `@Volatile` so writes from the Flutter platform thread (when the
    // engine attaches/detaches) are visible to readers on background
    // threads (sync executors, headless dispatch path). Without it, the
    // Java memory model permits a stale-cache `null` read after attach
    // — events would silently fall through to the headless dispatcher.
    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun sendEvent(event: Map<String, Any>) {
        val sink = eventSink
        if (sink == null) {
            headlessDispatcher.dispatch(event)
            return
        }
        mainHandler.post {
            sink.success(event)
        }
    }
}
