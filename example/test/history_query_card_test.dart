import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';
import 'package:locus_example/demos/history_query_card.dart';

List<Location> points(int count) => List.generate(
  count,
  (index) => Location(
    uuid: 'point-$index',
    timestamp: DateTime.utc(2026, 11, 3, 12, index),
    coords: const Coords(latitude: 52, longitude: 4, accuracy: 5),
  ),
);

Future<void> showCard(
  WidgetTester tester,
  Future<List<Location>> Function(LocationQuery) query, {
  Future<void> Function()? clear,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2E5D4B)),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SingleChildScrollView(
            child: StoredLocationsCard(
              query: query,
              onClear: clear ?? () async {},
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> press(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> select(WidgetTester tester, String current, String next) async {
  await press(tester, current);
  await tester.pumpAndSettle();
  await tester.tap(find.text(next).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bounded paging keeps a fixed window and resets for filters', (
    tester,
  ) async {
    final queries = <LocationQuery>[];
    await showCard(tester, (query) async {
      queries.add(query);
      return points(query.offset == 0 ? query.limit! : 1);
    });
    await select(tester, 'All history', 'Last hour');
    await select(tester, 'All motion', 'Moving');
    await tester.enterText(find.byType(TextFormField), '25');
    await press(tester, 'Apply query');
    await tester.pumpAndSettle();
    expect(queries.single.limit, 11);
    expect(queries.single.isMoving, isTrue);
    expect(queries.single.minAccuracy, 25);
    expect(
      queries.single.to!.difference(queries.single.from!),
      const Duration(hours: 1),
    );
    await press(tester, 'Next page');
    await tester.pumpAndSettle();
    expect(queries.last.offset, 10);
    expect(queries.last.to, queries.first.to);
    expect(queries.last.from, queries.first.from);
    expect(find.text('Page 2'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Next page'))
          .onPressed,
      isNull,
    );
    await press(tester, 'Previous page');
    await tester.pumpAndSettle();
    expect(queries.last.offset, 0);
    await select(tester, 'Newest first', 'Oldest first');
    expect(find.text('Page 1'), findsNothing);
    await press(tester, 'Apply query');
    await tester.pumpAndSettle();
    expect(queries.last.sortOrder, LocationSortOrder.oldestFirst);
    expect(queries.last.offset, 0);
    await select(tester, '10 locations', '25 locations');
    await press(tester, 'Apply query');
    await tester.pumpAndSettle();
    expect(queries.last.limit, 26);
    expect(queries.last.offset, 0);
  });

  testWidgets(
    'loading a new page disables pagers and ignores completion after disposal',
    (tester) async {
      final pending = Completer<List<Location>>();
      await showCard(
        tester,
        (query) =>
            query.offset == 0 ? Future.value(points(11)) : pending.future,
      );
      await press(tester, 'Apply query');
      await tester.pumpAndSettle();
      await press(tester, 'Next page');
      expect(find.text('Loading page 2'), findsOneWidget);
      expect(find.textContaining('52.00000, 4.00000'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply query'),
            )
            .onPressed,
        isNull,
      );
      for (final label in ['Previous page', 'Next page']) {
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, label))
              .onPressed,
          isNull,
        );
      }
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Clear all stored locations'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const MaterialApp(home: Text('Left Storage')));
      pending.complete(points(11));
      await tester.pumpAndSettle();
      expect(find.text('Left Storage'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'error retry uses the same query and empty result explains next action',
    (tester) async {
      final queries = <LocationQuery>[];
      await showCard(tester, (query) async {
        queries.add(query);
        if (queries.length == 1) throw StateError('Offline');
        return [];
      });
      await press(tester, 'Apply query');
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load history:'), findsOneWidget);
      await press(tester, 'Retry');
      await tester.pumpAndSettle();
      expect(queries.last.to, queries.first.to);
      expect(queries.last.offset, 0);
      expect(find.textContaining('No stored locations match.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    },
  );

  testWidgets('accuracy rejects nonfinite and negative input before querying', (
    tester,
  ) async {
    var calls = 0;
    await showCard(tester, (_) async {
      calls++;
      return [];
    });
    for (final invalid in ['NaN', 'Infinity', '-1']) {
      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), invalid);
      await press(tester, 'Apply query');
      expect(
        find.text('Enter a finite number of meters, 0 or greater'),
        findsOneWidget,
      );
    }
    expect(calls, 0);
  });

  testWidgets(
    'collapsed blank bounds reopen with field errors and do not query',
    (tester) async {
      var calls = 0;
      await showCard(tester, (_) async {
        calls++;
        return [];
      });
      await press(tester, 'Geographic bounds (optional)');
      await tester.pumpAndSettle();
      await press(tester, 'Filter by bounds');
      await tester.pumpAndSettle();
      await press(tester, 'Geographic bounds (optional)');
      await tester.pumpAndSettle();
      expect(find.text('South latitude'), findsNothing);
      await press(tester, 'Apply query');
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(tester.takeException(), isNull);
      expect(find.text('South latitude'), findsOneWidget);
      expect(find.text('Enter a number from -90.0 to 90.0'), findsNWidgets(2));
      expect(
        find.text('Enter a number from -180.0 to 180.0'),
        findsNWidgets(2),
      );
      expect(
        find.text('Check the highlighted fields before applying the query.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'collapsed bounds validate ranges and ordering, valid inclusive bounds query',
    (tester) async {
      final queries = <LocationQuery>[];
      await showCard(tester, (query) async {
        queries.add(query);
        return [];
      });
      await press(tester, 'Geographic bounds (optional)');
      await tester.pumpAndSettle();
      await press(tester, 'Filter by bounds');
      await tester.pumpAndSettle();
      Future<void> enter(String label, String value) async {
        final input = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(input);
        await tester.enterText(input, value);
      }

      await enter('South latitude', '91');
      await enter('North latitude', '10');
      await enter('West longitude', '20');
      await enter('East longitude', '10');
      await press(tester, 'Geographic bounds (optional)');
      await tester.pumpAndSettle();
      await press(tester, 'Apply query');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(queries, isEmpty);
      expect(find.text('Enter a number from -90.0 to 90.0'), findsOneWidget);
      expect(find.text('East must be at least west'), findsOneWidget);
      await enter('South latitude', '-90');
      await enter('North latitude', '90');
      await enter('West longitude', '-180');
      await enter('East longitude', '180');
      await press(tester, 'Geographic bounds (optional)');
      await tester.pumpAndSettle();
      expect(find.text('South latitude'), findsNothing);
      await press(tester, 'Apply query');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Check the highlighted fields before applying the query.'),
        findsNothing,
      );
      expect(queries.single.bounds!.southwest.latitude, -90);
      expect(queries.single.bounds!.northeast.longitude, 180);
    },
  );

  testWidgets('narrow large-text layout and clear-all callback remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var clears = 0;
    await showCard(
      tester,
      (_) async => points(1),
      clear: () async {
        clears++;
      },
      textScale: 2,
    );
    await press(tester, 'Apply query');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await press(tester, 'Clear all stored locations');
    await tester.pumpAndSettle();
    expect(clears, 1);
    expect(
      find.textContaining('including those outside this query'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
