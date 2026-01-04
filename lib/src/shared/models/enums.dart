enum ActivityType {
  still,
  onFoot,
  walking,
  running,
  inVehicle,
  onBicycle,
  tilting,
  unknown,
}

enum GeofenceAction {
  enter,
  exit,
  dwell,
  unknown,
}

enum ProviderAvailability {
  available,
  unavailable,
  denied,
  restricted,
  unknown,
}

enum AuthorizationStatus {
  notDetermined,
  restricted,
  denied,
  always,
  whenInUse,
  unknown,
}

enum LocationAccuracyAuthorization {
  full,
  reduced,
  unknown,
}
