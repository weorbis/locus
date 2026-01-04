# Installation

## Add Locus to your project

Add Locus to your `pubspec.yaml`:

```yaml
dependencies:
  locus: ^1.2.0
```

Or install via command line:

```bash
flutter pub add locus
```

## Platform Configuration

Locus requires platform-specific configuration to work correctly:

- **Android**: Requires location permissions, foreground service configuration, and battery optimization settings
- **iOS**: Requires location permissions and background modes

See [Platform Configuration](platform-configuration.md) for detailed setup instructions.

## Basic Usage

```dart
import 'package:locus/locus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Locus
  await Locus.ready();
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  Future<void> _startTracking() async {
    // Request permissions
    final hasPermission = await Locus.permission.request();
    if (!hasPermission) return;

    // Configure geolocation
    await Locus.config.set(
      GeolocationConfig(
        accuracy: Accuracy.best,
        distanceFilter: 10,
      ),
    );

    // Start tracking
    await Locus.start();

    // Listen to location updates
    Locus.onLocation((location) {
      print('${location.coords.latitude}, ${location.coords.longitude}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Locus')),
      body: Center(
        child: ElevatedButton(
          onPressed: _startTracking,
          child: const Text('Start Tracking'),
        ),
      ),
    );
  }
}
```

**Next:** [Quick Start Guide](../guides/quickstart.md)
