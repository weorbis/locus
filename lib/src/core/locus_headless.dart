import 'dart:async';
import 'dart:convert';
import 'dart:ui' show CallbackHandle, PluginUtilities;

import 'package:flutter/widgets.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/observability/locus_logger.dart';
import 'package:locus/src/core/locus_channels.dart';
import 'package:locus/src/core/locus_interface.dart';

final _log = locusLogger('headless');

/// Callback type for headless background events.
typedef HeadlessEventCallback = Future<void> Function(HeadlessEvent event);

/// Top-level headless dispatcher entry point.
///
/// Must be top-level (not a static method) because the native
/// `executeDartCallback` resolves the function via
/// `Dart_GetField(library, name)` which only finds top-level functions.
/// Static methods on a class are invisible to this lookup.
@pragma('vm:entry-point')
void headlessDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  LocusChannels.headless.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'headlessEvent':
        await _handleHeadlessEvent(call);
        return;
      case 'headlessBuildSyncBody':
        return _handleHeadlessBuildSyncBody(call);
      default:
        return;
    }
  });
  // Signal native side that the MethodChannel handler is ready to receive
  // events. Without this, the native HeadlessService may invoke
  // 'headlessEvent' before this handler is registered, losing the event.
  unawaited(
      LocusChannels.headless.invokeMethod<void>('dispatcher#initialized'));
}

Future<void> _handleHeadlessEvent(dynamic call) async {
  final args = Map<String, dynamic>.from(call.arguments as Map);
  final rawHandle = args['callbackHandle'] as int?;
  if (rawHandle == null) {
    return;
  }
  final handle = CallbackHandle.fromRawHandle(rawHandle);
  final callback = PluginUtilities.getCallbackFromHandle(handle) as Future<void>
      Function(HeadlessEvent)?;
  if (callback == null) {
    return;
  }
  try {
    final rawEvent = args['event'];
    if (rawEvent is String) {
      final decoded = json.decode(rawEvent) as Map<String, dynamic>;
      await callback(HeadlessEvent.fromMap(decoded));
    } else if (rawEvent is Map) {
      await callback(
          HeadlessEvent.fromMap(Map<String, dynamic>.from(rawEvent)));
    }
  } catch (error, stack) {
    _log.eventSevere('headless_event_dispatch_failed', const {}, error, stack);
  }
}

Future<dynamic> _handleHeadlessBuildSyncBody(dynamic call) async {
  final args = Map<String, dynamic>.from(call.arguments as Map);
  final rawHandle = args['callbackHandle'] as int?;

  if (rawHandle == null) {
    return null;
  }

  final handle = CallbackHandle.fromRawHandle(rawHandle);
  final callback = PluginUtilities.getCallbackFromHandle(handle);

  if (callback == null) {
    _log.eventWarning('headless_sync_body_callback_unresolved');
    return null;
  }

  try {
    final context = SyncBodyContext.fromMap(args);
    final typedCallback = callback as Future<JsonMap> Function(SyncBodyContext);
    final result = await typedCallback(context);
    return result;
  } catch (e, stack) {
    _log.eventSevere('headless_sync_body_builder_failed', const {}, e, stack);
    return null;
  }
}

/// Headless task management.
class LocusHeadless {
  /// Registers a headless task callback.
  ///
  /// The callback must be a **top-level or static function** (not a closure).
  /// Closures capture state that cannot be serialized for background execution.
  ///
  /// Returns `false` if registration fails, typically because:
  /// - The callback is a closure, not a top-level function
  /// - The callback is missing `@pragma('vm:entry-point')`
  static Future<bool> registerHeadlessTask(
      HeadlessEventCallback callback) async {
    final dispatcherHandle =
        PluginUtilities.getCallbackHandle(headlessDispatcher);
    final callbackHandle = PluginUtilities.getCallbackHandle(callback);

    if (dispatcherHandle == null || callbackHandle == null) {
      _log.eventSevere('headless_register_failed', const {
        'reason': 'callback_handle_null',
        'hint':
            'Callback must be a top-level or static function annotated with @pragma("vm:entry-point").',
      });
      return false;
    }

    final result = await LocusChannels.methods.invokeMethod(
      'registerHeadlessTask',
      {
        'dispatcher': dispatcherHandle.toRawHandle(),
        'callback': callbackHandle.toRawHandle(),
      },
    );

    if (result != true) {
      _log.eventWarning('headless_register_native_returned_false', const {
        'hint':
            'The native plugin may not support headless mode on this platform.',
      });
    }

    return result == true;
  }

  /// Starts a background task and returns its ID.
  static Future<int> startBackgroundTask() async {
    final result =
        await LocusChannels.methods.invokeMethod('startBackgroundTask');
    if (result is num) {
      return result.toInt();
    }
    return 0;
  }

  /// Stops a background task by ID.
  static Future<void> stopBackgroundTask(int taskId) async {
    await LocusChannels.methods.invokeMethod('stopBackgroundTask', taskId);
  }
}
