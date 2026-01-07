/// Service mocks for testing.
///
/// This library exports mock implementations of all locus services
/// for use in unit tests.
library;

// Note: Some service mocks are simplified versions that don't implement
// all optional methods to avoid compilation issues. They implement
// the core functionality needed for testing.

// Export the main MockLocus which includes service-like behavior
export 'package:locus/src/testing/testing.dart';

// Export service-specific mocks that extend functionality
// These are simplified for testing - use MockLocus for full integration testing
