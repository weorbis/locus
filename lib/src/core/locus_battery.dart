import 'package:locus/src/battery/battery.dart';
import 'package:locus/src/events/events.dart'; // Added import
// import 'package:locus/src/models/models.dart'; // Unused
import 'locus_channels.dart';
import 'locus_streams.dart';

/// Battery and Power management.
class LocusBattery {
  /// Gets battery usage statistics since tracking started.
  static Future<BatteryStats> getBatteryStats() async {
    final result = await LocusChannels.methods.invokeMethod('getBatteryStats');
    if (result is Map) {
      return BatteryStats.fromMap(Map<String, dynamic>.from(result));
    }
    return const BatteryStats.empty();
  }

  /// Gets the current power state of the device.
  static Future<PowerState> getPowerState() async {
    final result = await LocusChannels.methods.invokeMethod('getPowerState');
    if (result is Map) {
      return PowerState.fromMap(Map<String, dynamic>.from(result));
    }
    return PowerState.unknown;
  }

  /// Stream of power state changes.
  static Stream<PowerStateChangeEvent> get powerStateStream {
    return LocusStreams.events
        .where((event) => event.type == EventType.powerSaveChange)
        .map((event) {
      if (event.data is PowerStateChangeEvent) {
        return event.data as PowerStateChangeEvent;
      }
      // Create synthetic event from power save boolean
      final isPowerSave = event.data == true;
      return PowerStateChangeEvent(
        previous: PowerState.unknown,
        current: PowerState(
          batteryLevel: 50,
          isCharging: false,
          isPowerSaveMode: isPowerSave,
        ),
        changeType: PowerStateChangeType.powerSaveMode,
      );
    });
  }
}
