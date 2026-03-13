# Quick Start Guide

Get up and running with Locus in minutes.

## 1. Installation

Add `locus` to your `pubspec.yaml`:

```yaml
dependencies:
  locus: ^2.1.4
```

## 2. Automated Setup

Run the CLI tool to configure platform permissions:

```bash
dart run locus:setup
```

## 3. Basic Usage

### Request Permissions

Locus requires location and background permissions. The `requestPermission` helper handles the platform-specific logic.

```dart
import 'package:locus/locus.dart';

final granted = await Locus.requestPermission();
```

### Initialize and Start

Initialize the SDK with a configuration preset and start tracking.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use a balanced preset for typical tracking needs
  await Locus.ready(ConfigPresets.balanced.copyWith(
    url: 'https://api.yourservice.com/locations',
    notification: NotificationConfig(
      title: 'Location Service',
      text: 'Tracking is active',
    ),
  ));

  await Locus.start();
}
```

## 4. Listen for Updates

```dart
Locus.location.stream.listen((location) {
  print('New Location: ${location.coords.latitude}, ${location.coords.longitude}');
});

Locus.location.motionChanges.listen((location) {
  print('Moving: ${location.isMoving} (${location.activity.type})');
});
```

---

**Next:** [Advanced Configuration](../core/configuration.md)
