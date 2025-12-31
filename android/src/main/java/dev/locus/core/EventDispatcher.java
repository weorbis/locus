package dev.locus.core;

import android.os.Handler;
import android.os.Looper;

import java.util.Map;

import io.flutter.plugin.common.EventChannel;

public class EventDispatcher {
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final HeadlessDispatcher headlessDispatcher;
    private EventChannel.EventSink eventSink;

    public EventDispatcher(HeadlessDispatcher headlessDispatcher) {
        this.headlessDispatcher = headlessDispatcher;
    }

    public void setEventSink(EventChannel.EventSink eventSink) {
        this.eventSink = eventSink;
    }

    public void sendEvent(Map<String, Object> event) {
        if (eventSink == null) {
            headlessDispatcher.dispatch(event);
            return;
        }
        mainHandler.post(() -> {
            if (eventSink != null) {
                eventSink.success(event);
            }
        });
    }
}
