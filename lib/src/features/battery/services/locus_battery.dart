import 'package:locus/src/features/battery/battery.dart';
import 'package:locus/src/shared/events.dart';
import 'package:locus/src/core/locus_channels.dart';
import 'package:locus/src/core/locus_streams.dart';

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

  /// Estimates remaining battery runway for tracking.
  ///
  /// Returns predictions for how long tracking can continue at current
  /// and low power rates, along with recommendations.
  static Future<BatteryRunway> estimateBatteryRunway() async {
    final stats = await getBatteryStats();
    final powerState = await getPowerState();

    return BatteryRunwayCalculator.calculate(
      currentLevel: stats.currentBatteryLevel ?? powerState.batteryLevel,
      isCharging: stats.isCharging ?? powerState.isCharging,
      drainPercent: stats.estimatedDrainPercent,
      trackingMinutes: stats.trackingDurationMinutes,
    );
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
