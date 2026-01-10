/// Test helpers for working with async operations.
///
/// Provides utilities for waiting on streams, futures, and
/// testing async behavior.
library;

import 'dart:async';

/// Waits for a stream to emit a specific value or match a condition.
///
/// Example:
/// ```dart
/// await waitForStreamValue(
///   mock.locationStream,
///   (location) => location.coords.latitude > 37.0,
///   timeout: Duration(seconds: 5),
/// );
/// ```
Future<T> waitForStreamValue<T>(
  Stream<T> stream,
  bool Function(T value) predicate, {
  Duration timeout = const Duration(seconds: 10),
  String? description,
}) async {
  final completer = Completer<T>();
  StreamSubscription<T>? subscription;
  Timer? timer;

  timer = Timer(timeout, () async {
    if (!completer.isCompleted) {
      await subscription?.cancel();
      completer.completeError(
        TimeoutException(
          description ?? 'Timed out waiting for stream value',
          timeout,
        ),
      );
    }
  });

  subscription = stream.listen(
    (value) async {
      if (predicate(value) && !completer.isCompleted) {
        timer?.cancel();
        await subscription?.cancel();
        completer.complete(value);
      }
    },
    onError: (error) async {
      if (!completer.isCompleted) {
        timer?.cancel();
        await subscription?.cancel();
        completer.completeError(error);
      }
    },
    cancelOnError: true,
  );

  return completer.future;
}

/// Waits for a stream to emit N values.
///
/// Example:
/// ```dart
/// final locations = await waitForStreamCount(
///   mock.locationStream,
///   count: 5,
/// );
/// expect(locations.length, 5);
/// ```
Future<List<T>> waitForStreamCount<T>(
  Stream<T> stream, {
  required int count,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final values = <T>[];
  final completer = Completer<List<T>>();
  StreamSubscription<T>? subscription;
  Timer? timer;

  timer = Timer(timeout, () async {
    if (!completer.isCompleted) {
      await subscription?.cancel();
      completer.completeError(
        TimeoutException(
          'Timed out waiting for $count stream values (got ${values.length})',
          timeout,
        ),
      );
    }
  });

  subscription = stream.listen(
    (value) async {
      values.add(value);
      if (values.length >= count && !completer.isCompleted) {
        timer?.cancel();
        await subscription?.cancel();
        completer.complete(values);
      }
    },
    onError: (error) async {
      if (!completer.isCompleted) {
        timer?.cancel();
        await subscription?.cancel();
        completer.completeError(error);
      }
    },
    cancelOnError: true,
  );

  return completer.future;
}

/// Waits for a Future to complete or times out.
///
/// Example:
/// ```dart
/// final result = await waitForFuture(
///   someAsyncOperation(),
///   timeout: Duration(seconds: 5),
/// );
/// ```
Future<T> waitForFuture<T>(
  Future<T> future, {
  Duration timeout = const Duration(seconds: 10),
  String? description,
}) async {
  return future.timeout(
    timeout,
    onTimeout: () => throw TimeoutException(
      description ?? 'Future timed out',
      timeout,
    ),
  );
}

/// Polls a condition until it returns true or times out.
///
/// Example:
/// ```dart
/// await pollUntil(
///   () => mock.isReady,
///   interval: Duration(milliseconds: 100),
///   timeout: Duration(seconds: 5),
/// );
/// ```
Future<void> pollUntil(
  bool Function() condition, {
  Duration interval = const Duration(milliseconds: 100),
  Duration timeout = const Duration(seconds: 10),
  String? description,
}) async {
  final stopwatch = Stopwatch()..start();

  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException(
        description ?? 'Condition not met within timeout',
        timeout,
      );
    }
    await Future.delayed(interval);
  }
}

/// Polls an async condition until it returns true or times out.
///
/// Example:
/// ```dart
/// await pollUntilAsync(
///   () async => (await mock.getState()).enabled,
///   interval: Duration(milliseconds: 100),
///   timeout: Duration(seconds: 5),
/// );
/// ```
Future<void> pollUntilAsync(
  Future<bool> Function() condition, {
  Duration interval = const Duration(milliseconds: 100),
  Duration timeout = const Duration(seconds: 10),
  String? description,
}) async {
  final stopwatch = Stopwatch()..start();

  while (!(await condition())) {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException(
        description ?? 'Async condition not met within timeout',
        timeout,
      );
    }
    await Future.delayed(interval);
  }
}

/// Waits for a period and then checks if a stream has emitted.
///
/// Useful for verifying that something DOESN'T happen.
///
/// Example:
/// ```dart
/// await expectNoStreamEvents(
///   mock.locationStream,
///   duration: Duration(seconds: 2),
/// );
/// ```
Future<void> expectNoStreamEvents<T>(
  Stream<T> stream, {
  Duration duration = const Duration(seconds: 1),
}) async {
  final events = <T>[];
  final subscription = stream.listen(events.add);

  await Future.delayed(duration);
  await subscription.cancel();

  if (events.isNotEmpty) {
    throw AssertionError(
      'Expected no stream events but got ${events.length}: $events',
    );
  }
}

/// Collects all stream events for a duration.
///
/// Example:
/// ```dart
/// final events = await collectStreamEvents(
///   mock.locationStream,
///   duration: Duration(seconds: 5),
/// );
/// expect(events.length, greaterThan(0));
/// ```
Future<List<T>> collectStreamEvents<T>(
  Stream<T> stream, {
  Duration duration = const Duration(seconds: 1),
}) async {
  final events = <T>[];
  final subscription = stream.listen(events.add);

  await Future.delayed(duration);
  await subscription.cancel();

  return events;
}

/// Runs an action and waits for a stream event as a result.
///
/// Example:
/// ```dart
/// final location = await expectStreamEventFrom(
///   mock.locationStream,
///   () => mock.emitLocation(testLocation),
/// );
/// expect(location.coords.latitude, testLocation.coords.latitude);
/// ```
Future<T> expectStreamEventFrom<T>(
  Stream<T> stream,
  Future<void> Function() action, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final future = stream.first.timeout(timeout);
  await action();
  return future;
}

/// Debounces a stream for testing.
///
/// Example:
/// ```dart
/// final debounced = debounceStream(
///   mock.locationStream,
///   duration: Duration(milliseconds: 500),
/// );
/// ```
Stream<T> debounceStream<T>(
  Stream<T> stream, {
  required Duration duration,
}) {
  final controller = StreamController<T>();
  Timer? debounceTimer;
  T? lastValue;

  stream.listen(
    (value) {
      lastValue = value;
      debounceTimer?.cancel();
      debounceTimer = Timer(duration, () {
        if (lastValue != null) {
          controller.add(lastValue as T);
        }
      });
    },
    onError: controller.addError,
    onDone: () async {
      debounceTimer?.cancel();
      await controller.close();
    },
    cancelOnError: true,
  );

  return controller.stream;
}
