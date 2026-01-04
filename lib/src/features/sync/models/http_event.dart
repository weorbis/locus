import 'package:locus/src/shared/models/json_map.dart';

class HttpEvent {
  final int status;
  final bool ok;
  final String? responseText;
  final JsonMap? response;

  const HttpEvent({
    required this.status,
    required this.ok,
    this.responseText,
    this.response,
  });

  JsonMap toMap() => {
        'status': status,
        'ok': ok,
        if (responseText != null) 'responseText': responseText,
        if (response != null) 'response': response,
      };

  factory HttpEvent.fromMap(JsonMap map) {
    return HttpEvent(
      status: (map['status'] as num?)?.toInt() ?? 0,
      ok: map['ok'] as bool? ?? false,
      responseText: map['responseText'] as String?,
      response: map['response'] as JsonMap?,
    );
  }
}
