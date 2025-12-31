import '../common/enums.dart';
import '../common/json_map.dart';

class ProviderChangeEvent {
  final bool enabled;
  final String? status;
  final ProviderAvailability availability;
  final AuthorizationStatus authorizationStatus;
  final LocationAccuracyAuthorization accuracyAuthorization;

  const ProviderChangeEvent({
    required this.enabled,
    this.status,
    required this.availability,
    required this.authorizationStatus,
    required this.accuracyAuthorization,
  });

  JsonMap toMap() => {
        'enabled': enabled,
        if (status != null) 'status': status,
        'availability': availability.name,
        'authorizationStatus': authorizationStatus.name,
        'accuracyAuthorization': accuracyAuthorization.name,
      };

  factory ProviderChangeEvent.fromMap(JsonMap map) {
    return ProviderChangeEvent(
      enabled: map['enabled'] as bool? ?? false,
      status: map['status'] as String?,
      availability: ProviderAvailability.values.firstWhere(
        (value) => value.name == map['availability'],
        orElse: () => ProviderAvailability.unknown,
      ),
      authorizationStatus: AuthorizationStatus.values.firstWhere(
        (value) => value.name == map['authorizationStatus'],
        orElse: () => AuthorizationStatus.unknown,
      ),
      accuracyAuthorization: LocationAccuracyAuthorization.values.firstWhere(
        (value) => value.name == map['accuracyAuthorization'],
        orElse: () => LocationAccuracyAuthorization.unknown,
      ),
    );
  }
}
