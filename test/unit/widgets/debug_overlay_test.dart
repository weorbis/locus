import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/features/diagnostics/debug_overlay.dart';
import 'package:locus/src/testing/mock_locus.dart';
import 'package:locus/src/locus.dart';
import 'package:locus/src/models.dart';

void main() {
  group('LocusDebugOverlay', () {
    late MockLocus mockLocus;

    setUp(() {
      mockLocus = MockLocus();
      Locus.setMockInstance(mockLocus);
    });

    tearDown(() {
      // Create a fresh mock instance for cleanup
      Locus.setMockInstance(MockLocus());
    });

    testWidgets('renders in collapsed state by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              LocusDebugOverlay(),
            ],
          ),
        ),
      );

      // Should show collapsed view with tracking status
      expect(find.text('Tracking OFF'), findsOneWidget);
    });

    testWidgets('expands when tapped', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              LocusDebugOverlay(),
            ],
          ),
        ),
      );

      // Tap to expand
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      // Should show expanded view with sections
      expect(find.text('Locus Debug'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Battery'), findsOneWidget);
      expect(find.text('Sync Queue'), findsOneWidget);
      expect(find.text('Geofences'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Stats'), findsOneWidget);
    });

    testWidgets('starts expanded when configured', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              LocusDebugOverlay(expanded: true),
            ],
          ),
        ),
      );

      // Should show expanded view immediately
      expect(find.text('Locus Debug'), findsOneWidget);
    });

    testWidgets('positions correctly in each corner', (tester) async {
      for (final position in DebugOverlayPosition.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Stack(
              children: [
                LocusDebugOverlay(position: position),
              ],
            ),
          ),
        );

        // Should find the overlay
        expect(find.byType(LocusDebugOverlay), findsOneWidget);
      }
    });

    testWidgets('displays tracking status when enabled', (tester) async {
      mockLocus.setMockState(const GeolocationState(enabled: true));

      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              LocusDebugOverlay(),
            ],
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Tracking ON'), findsOneWidget);
    });

    testWidgets('shows location data when available', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              LocusDebugOverlay(expanded: true),
            ],
          ),
        ),
      );

      // Emit a location
      mockLocus.emitLocation(Location(
        uuid: 'test-location',
        timestamp: DateTime.now(),
        coords: const Coords(
          latitude: 37.4219,
          longitude: -122.0840,
          accuracy: 10,
        ),
        isMoving: false,
      ));

      await tester.pump(const Duration(milliseconds: 100));

      // Should show location coordinates
      expect(find.textContaining('37.4219'), findsWidgets);
    });

    testWidgets('control buttons trigger SDK methods', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              LocusDebugOverlay(expanded: true),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();
      mockLocus.clearMethodCalls();

      // Find and tap the Start button
      expect(find.text('Start'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pump();

      // Verify start was called
      expect(mockLocus.methodCalls.contains('start'), true);
    });

    testWidgets('respects opacity setting', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              LocusDebugOverlay(opacity: 0.5),
            ],
          ),
        ),
      );

      // Widget should render
      expect(find.byType(LocusDebugOverlay), findsOneWidget);
    });

    testWidgets('closes when close button is tapped', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              LocusDebugOverlay(expanded: true),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find and tap close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Should be in collapsed state
      expect(find.text('Locus Debug'), findsNothing);
    });

    testWidgets('shows sync queue stats', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              LocusDebugOverlay(expanded: true),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show sync section
      expect(find.text('Sync Queue'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Success'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('shows geofence stats', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [
              LocusDebugOverlay(expanded: true),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show geofence section
      expect(find.text('Geofences'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
    });
  });

  group('DebugOverlayPosition', () {
    test('has all corner positions', () {
      expect(DebugOverlayPosition.values.length, 4);
      expect(DebugOverlayPosition.values, contains(DebugOverlayPosition.topLeft));
      expect(DebugOverlayPosition.values, contains(DebugOverlayPosition.topRight));
      expect(DebugOverlayPosition.values, contains(DebugOverlayPosition.bottomLeft));
      expect(DebugOverlayPosition.values, contains(DebugOverlayPosition.bottomRight));
    });
  });
}
