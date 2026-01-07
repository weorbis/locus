/// Base test classes for consistent test setup and teardown.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';

/// Base class for service-level unit tests.
///
/// Provides common setup and teardown for testing services.
///
/// Example:
/// ```dart
/// class MyServiceTest extends BaseServiceTest {
///   late MyService service;
///
///   @override
///   void additionalSetup() {
///     service = MyService(mockLocus);
///   }
///
///   @override
///   void additionalTearDown() {
///     service.dispose();
///   }
/// }
/// ```
abstract class BaseServiceTest {
  late MockLocus mockLocus;

  /// Called before each test.
  void baseSetUp() {
    mockLocus = MockLocus();
    additionalSetup();
  }

  /// Called after each test.
  Future<void> baseTearDown() async {
    additionalTearDown();
    await mockLocus.dispose();
  }

  /// Override this to add additional setup logic.
  void additionalSetup() {}

  /// Override this to add additional teardown logic.
  void additionalTearDown() {}

  /// Helper to run a test with automatic setup/teardown.
  void serviceTest(
    String description,
    Future<void> Function() body, {
    dynamic skip,
    Timeout? timeout,
  }) {
    test(
      description,
      () async {
        baseSetUp();
        try {
          await body();
        } finally {
          await baseTearDown();
        }
      },
      skip: skip,
      timeout: timeout,
    );
  }
}

/// Base class for integration tests.
///
/// Provides setup for tests that need full Locus SDK integration.
///
/// Example:
/// ```dart
/// class MyIntegrationTest extends BaseIntegrationTest {
///   @override
///   Config createTestConfig() {
///     return const Config(
///       distanceFilter: 10,
///       desiredAccuracy: DesiredAccuracy.high,
///     );
///   }
/// }
/// ```
abstract class BaseIntegrationTest {
  late MockLocus mockLocus;
  late Config testConfig;

  /// Called before each test.
  void baseSetUp() {
    mockLocus = MockLocus();
    testConfig = createTestConfig();
    additionalSetup();
  }

  /// Called after each test.
  Future<void> baseTearDown() async {
    additionalTearDown();
    await mockLocus.dispose();
  }

  /// Override this to create a custom test configuration.
  Config createTestConfig() {
    return const Config(
      desiredAccuracy: DesiredAccuracy.medium,
      distanceFilter: 30,
    );
  }

  /// Override this to add additional setup logic.
  void additionalSetup() {}

  /// Override this to add additional teardown logic.
  void additionalTearDown() {}

  /// Helper to run an integration test with automatic setup/teardown.
  void integrationTest(
    String description,
    Future<void> Function() body, {
    dynamic skip,
    Timeout? timeout,
  }) {
    test(
      description,
      () async {
        baseSetUp();
        try {
          // Initialize mock with config
          await mockLocus.ready(testConfig);
          await body();
        } finally {
          await baseTearDown();
        }
      },
      skip: skip,
      timeout: timeout,
    );
  }
}

/// Helper function to group service tests with automatic setup/teardown.
///
/// Example:
/// ```dart
/// void main() {
///   serviceTestGroup<MyService>(
///     'MyService',
///     (getMock, getService) {
///       test('does something', () async {
///         final service = getService();
///         // ... test code
///       });
///     },
///     createService: (mock) => MyService(mock),
///   );
/// }
/// ```
void serviceTestGroup<T>(
  String description,
  void Function(MockLocus Function() getMock, T Function() getService) body, {
  required T Function(MockLocus mock) createService,
}) {
  group(description, () {
    late MockLocus mockLocus;
    late T service;

    setUp(() {
      mockLocus = MockLocus();
      service = createService(mockLocus);
    });

    tearDown(() async {
      await mockLocus.dispose();
    });

    body(() => mockLocus, () => service);
  });
}
