import 'package:locus/src/config/config.dart';
import 'locus_channels.dart';

/// Configuration management.
class LocusConfig {
  /// Updates the configuration.
  static Future<void> setConfig(Config config) async {
    await LocusChannels.methods.invokeMethod('setConfig', config.toMap());
  }

  /// Resets configuration to defaults, then applies the given config.
  static Future<void> reset(Config config) async {
    await LocusChannels.methods.invokeMethod('reset', config.toMap());
  }
}
