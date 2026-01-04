library;

import 'package:locus/src/models.dart';

/// Configuration for the foreground notification (Android).
class NotificationConfig {
  /// Notification title.
  final String? title;

  /// Notification text/body.
  final String? text;

  /// Small icon resource name.
  final String? smallIcon;

  /// Large icon resource name.
  final String? largeIcon;

  /// Custom layout resource name.
  final String? layout;

  /// List of action button identifiers.
  final List<String>? actions;

  /// Localized strings for notification.
  final JsonMap? strings;

  /// Notification importance (Android): 1=Low, 2=Default, 3=High.
  final int? importance;

  const NotificationConfig({
    this.title,
    this.text,
    this.smallIcon,
    this.largeIcon,
    this.layout,
    this.actions,
    this.strings,
    this.importance,
  });

  JsonMap toMap() => {
        if (title != null) 'title': title,
        if (text != null) 'text': text,
        if (smallIcon != null) 'smallIcon': smallIcon,
        if (largeIcon != null) 'largeIcon': largeIcon,
        if (layout != null) 'layout': layout,
        if (actions != null) 'actions': actions,
        if (strings != null) 'strings': strings,
        if (importance != null) 'importance': importance,
      };

  factory NotificationConfig.fromMap(JsonMap map) {
    JsonMap? asJsonMap(dynamic value) {
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      return null;
    }

    return NotificationConfig(
      title: map['title'] as String?,
      text: map['text'] as String?,
      smallIcon: map['smallIcon'] as String?,
      largeIcon: map['largeIcon'] as String?,
      layout: map['layout'] as String?,
      actions: (map['actions'] as List?)?.cast<String>(),
      strings: asJsonMap(map['strings']),
      importance: map['importance'] as int?,
    );
  }
}
