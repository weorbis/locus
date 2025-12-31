import 'package:locus/src/models/models.dart';
import 'locus_channels.dart';
import 'locus_lifecycle.dart';
import 'locus_sync.dart';
import 'locus_location.dart';

/// Diagnostics and Remote Commands.
class LocusDiagnostics {
  /// Captures a diagnostics snapshot for debugging/support.
  static Future<DiagnosticsSnapshot> getDiagnostics() async {
    final state = await LocusLifecycle.getState();
    final queue = await LocusSync.getQueue(limit: 50);
    final config = await _getConfigSnapshot();
    final metadata = await _getDiagnosticsMetadata();

    return DiagnosticsSnapshot(
      capturedAt: DateTime.now().toUtc(),
      state: state,
      config: config,
      queue: queue,
      metadata: metadata,
    );
  }

  static Future<JsonMap?> _getConfigSnapshot() async {
    final result = await LocusChannels.methods.invokeMethod('getConfig');
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return null;
  }

  static Future<JsonMap?> _getDiagnosticsMetadata() async {
    final result =
        await LocusChannels.methods.invokeMethod('getDiagnosticsMetadata');
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return null;
  }

  /// Applies a remote command payload.
  static Future<bool> applyRemoteCommand(RemoteCommand command) async {
    switch (command.type) {
      case RemoteCommandType.setConfig:
        if (command.payload == null) {
          return false;
        }
        await LocusChannels.methods.invokeMethod('setConfig', command.payload!);
        return true;
      case RemoteCommandType.syncQueue:
        await LocusSync.syncQueue();
        return true;
      case RemoteCommandType.emailLog:
        final email = command.payload?['email'] as String?;
        if (email == null || email.isEmpty) {
          return false;
        }
        await LocusChannels.methods.invokeMethod('emailLog', email);
        return true;
      case RemoteCommandType.setOdometer:
        final value = command.payload?['value'] as num?;
        if (value == null) {
          return false;
        }
        await LocusLocation.setOdometer(value.toDouble());
        return true;
      case RemoteCommandType.resetOdometer:
        await LocusLocation.setOdometer(0);
        return true;
    }
  }
}
