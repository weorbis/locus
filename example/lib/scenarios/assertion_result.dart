import 'package:flutter/foundation.dart';

/// Outcome of a single check inside a scenario's `verify` phase.
///
/// Scenarios produce a list of these — one per logical assertion — and the
/// runner aggregates them. A scenario passes when every assertion is
/// [AssertionStatus.pass]; any [AssertionStatus.fail] makes the scenario
/// fail. [AssertionStatus.skip] is for inherently-platform-specific or
/// preconditions-not-met checks that should be reported but not fail.
enum AssertionStatus { pass, fail, skip }

@immutable
class AssertionResult {
  const AssertionResult.pass(this.description)
      : status = AssertionStatus.pass,
        failureDetail = null,
        expected = null,
        actual = null;

  const AssertionResult.fail(
    this.description, {
    required this.failureDetail,
    this.expected,
    this.actual,
  })  : status = AssertionStatus.fail;

  const AssertionResult.skip(this.description, {required this.failureDetail})
      : status = AssertionStatus.skip,
        expected = null,
        actual = null;

  /// Short, human-readable description of what this assertion checks.
  /// Conventionally written in the third person ("HTTP layer paused
  /// after 401", not "I expect the HTTP layer to pause after 401").
  final String description;

  final AssertionStatus status;

  /// Why the assertion failed or was skipped. `null` when [status] is pass.
  final String? failureDetail;

  /// Optional structured context for failure rendering. Keep cheap to
  /// `toString` — these get displayed in the runner UI.
  final Object? expected;
  final Object? actual;

  bool get passed => status == AssertionStatus.pass;
  bool get failed => status == AssertionStatus.fail;

  Map<String, Object?> toJson() => <String, Object?>{
        'description': description,
        'status': status.name,
        if (failureDetail != null) 'failureDetail': failureDetail,
        if (expected != null) 'expected': expected.toString(),
        if (actual != null) 'actual': actual.toString(),
      };
}
