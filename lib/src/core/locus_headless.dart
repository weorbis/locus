import 'dart:async';
import 'dart:convert';
import 'dart:ui' show CallbackHandle, PluginUtilities;

import 'package:flutter/widgets.dart';
import 'package:locus/src/models/models.dart';
import 'locus_channels.dart';

/// Callback type for headless background events.
typedef HeadlessEventCallback = Future<void> Function(HeadlessEvent event);

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
      debugPrint('[Locus] ERROR: Failed to register headless task.');
      debugPrint('[Locus]   Could not obtain callback handles.');
      debugPrint(
          '[Locus]   Ensure your callback is a top-level or static function, not a closure.');
      debugPrint('[Locus]   Example:');
      debugPrint('[Locus]     @pragma("vm:entry-point")');
      debugPrint(
          '[Locus]     Future<void> myHeadlessTask(HeadlessEvent event) async { ... }');
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
      debugPrint(
          '[Locus] WARNING: Native headless registration returned false.');
      debugPrint(
          '[Locus]   The native plugin may not support headless mode on this platform.');
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

  @pragma('vm:entry-point')
  static void headlessDispatcher() {
    WidgetsFlutterBinding.ensureInitialized();
    LocusChannels.headless.setMethodCallHandler((call) async {
      if (call.method != 'headlessEvent') {
        return;
      }
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final rawHandle = args['callbackHandle'] as int?;
      if (rawHandle == null) {
        return;
      }
      final handle = CallbackHandle.fromRawHandle(rawHandle);
      final callback = PluginUtilities.getCallbackFromHandle(handle)
          as Future<void> Function(HeadlessEvent)?;
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
      } catch (error) {
        debugPrint('Locus headless error: $error');
      }
    });
  }
}
