package dev.locus.core

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

class EventDispatcher(
    private val headlessDispatcher: HeadlessDispatcher
) {
    private val mainHandler = Handler(Looper.getMainLooper())
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
