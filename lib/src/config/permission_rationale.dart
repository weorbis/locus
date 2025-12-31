library;

import 'package:locus/src/models/models.dart';

/// Configuration for permission rationale dialog.
class PermissionRationale {
  /// Title of the dialog.
  final String title;

  /// Message explaining why permission is needed.
  final String message;

  /// Text for the positive action button.
  final String? positiveAction;

  /// Text for the negative action button.
  final String? negativeAction;

  const PermissionRationale({
    required this.title,
    required this.message,
    this.positiveAction,
    this.negativeAction,
  });

  JsonMap toMap() => {
        'title': title,
        'message': message,
        if (positiveAction != null) 'positiveAction': positiveAction,
        if (negativeAction != null) 'negativeAction': negativeAction,
      };

  factory PermissionRationale.fromMap(JsonMap map) {
    return PermissionRationale(
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      positiveAction: map['positiveAction'] as String?,
      negativeAction: map['negativeAction'] as String?,
    );
  }
}
