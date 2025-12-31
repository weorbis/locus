package dev.locus.service;

import android.content.Context;
import android.content.Intent;

import androidx.annotation.NonNull;
import androidx.core.app.JobIntentService;

import java.util.HashMap;
import java.util.Map;

import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.FlutterCallbackInformation;

public class HeadlessService extends JobIntentService {
    private static final String CHANNEL = "locus/headless";
    private static final int JOB_ID = 197812512;

    public static void enqueueWork(Context context, Intent intent) {
        enqueueWork(context, HeadlessService.class, JOB_ID, intent);
    }

    @Override
    protected void onHandleWork(@NonNull Intent intent) {
        long dispatcherHandle = intent.getLongExtra("dispatcher", 0L);
        long callbackHandle = intent.getLongExtra("callback", 0L);
        if (dispatcherHandle == 0L || callbackHandle == 0L) {
            return;
        }

        FlutterEngine engine = FlutterEngineCache.getInstance().get("locus_headless_engine");
        if (engine == null) {
            FlutterInjector injector = FlutterInjector.instance();
            injector.flutterLoader().startInitialization(getApplicationContext());
            injector.flutterLoader().ensureInitializationComplete(getApplicationContext(), null);
            String appBundlePath = injector.flutterLoader().findAppBundlePath();
            FlutterCallbackInformation info =
                    FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle);
            if (info == null) {
                return;
            }
            engine = new FlutterEngine(getApplicationContext());
            DartExecutor.DartCallback callback = new DartExecutor.DartCallback(
                    getAssets(),
                    appBundlePath,
                    info
            );
            engine.getDartExecutor().executeDartCallback(callback);
            FlutterEngineCache.getInstance().put("locus_headless_engine", engine);
        }

        MethodChannel channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        String rawEvent = intent.getStringExtra("event");
        Map<String, Object> args = new HashMap<>();
        args.put("callbackHandle", callbackHandle);
        if (rawEvent != null) {
            args.put("event", rawEvent);
        } else {
            args.put("event", "{\"type\":\"boot\"}");
        }
        channel.invokeMethod("headlessEvent", args);
    }
}
