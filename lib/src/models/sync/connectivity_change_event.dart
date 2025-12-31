import '../common/json_map.dart';

class ConnectivityChangeEvent {
  final bool connected;
  final String? networkType;

  const ConnectivityChangeEvent({
    required this.connected,
    this.networkType,
  });

  JsonMap toMap() => {
        'connected': connected,
        if (networkType != null) 'networkType': networkType,
      };

  factory ConnectivityChangeEvent.fromMap(JsonMap map) {
    return ConnectivityChangeEvent(
      connected: map['connected'] as bool? ?? false,
      networkType: map['networkType'] as String?,
    );
  }
}
