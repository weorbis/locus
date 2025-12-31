import 'locus_channels.dart';

/// Scheduler management.
class LocusScheduler {
  /// Starts the schedule.
  static Future<bool> startSchedule() async {
    final result = await LocusChannels.methods.invokeMethod('startSchedule');
    return result == true;
  }

  /// Stops the schedule.
  static Future<bool> stopSchedule() async {
    final result = await LocusChannels.methods.invokeMethod('stopSchedule');
    return result == true;
  }
}
