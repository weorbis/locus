import 'dart:convert';

const defaultIntervalSeconds = 1.0;
const _maxLatitude = 90.0;
const _maxLongitude = 180.0;

class RoutePoint {
  RoutePoint(this.latitude, this.longitude, {this.altitude, this.time}) {
    if (!latitude.isFinite ||
        latitude.abs() > _maxLatitude ||
        !longitude.isFinite ||
        longitude.abs() > _maxLongitude ||
        (altitude != null && !altitude!.isFinite)) {
      throw const FormatException('Invalid coordinate or altitude.');
    }
  }

  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime? time;

  String get pair => '$latitude,$longitude';
}

List<RoutePoint> parseRoute(String source) {
  final text = source.trim().replaceFirst(RegExp(r'^\uFEFF'), '');
  final points = text.startsWith('<') ? _parseGpx(text) : _parseJson(text);
  if (points.isEmpty) {
    throw const FormatException('Route contains no locations.');
  }
  return points;
}

List<RoutePoint> _parseJson(String source) {
  final Object? document = jsonDecode(source);
  final Object? rows;
  var recorder = false;
  if (document is Map<String, Object?> && document.containsKey('events')) {
    rows = document['events'];
    recorder = true;
  } else {
    rows = document;
  }
  if (rows is! List<Object?>) {
    throw const FormatException('Expected a JSON array or recorder events.');
  }
  final points = <RoutePoint>[];
  for (final row in rows) {
    if (row is! Map<String, Object?>) {
      throw const FormatException('Each route entry must be an object.');
    }
    Map<String, Object?> location = row;
    if (recorder) {
      if (row['category'] != 'location' || row['type'] != 'location_update') {
        continue;
      }
      final payload = row['payload'];
      if (payload is! Map<String, Object?>) {
        throw const FormatException('Location event has no payload.');
      }
      location = payload;
    }
    final coords = location['coords'] ?? location;
    if (coords is! Map<String, Object?>) {
      throw const FormatException('Location coords must be an object.');
    }
    points.add(
      RoutePoint(
        _number(coords['lat'] ?? coords['latitude'], 'latitude'),
        _number(
          coords['lng'] ?? coords['lon'] ?? coords['longitude'],
          'longitude',
        ),
        altitude: _optionalNumber(
          coords['ele'] ?? coords['altitude'],
          'altitude',
        ),
        time: _time(
          location['ts'] ??
              location['timestamp'] ??
              (recorder ? row['at'] : null),
        ),
      ),
    );
  }
  return points;
}

double _number(Object? value, String name) {
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('$name must be a finite number.');
}

double? _optionalNumber(Object? value, String name) =>
    value == null ? null : _number(value, name);

// GPX times are UTC by definition, so a time without a zone is read as UTC.
DateTime? _time(Object? value) {
  if (value == null) return null;
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value)) {
    throw const FormatException('Time must be an ISO 8601 date-time string.');
  }
  final hasZone = RegExp(
    r'(?:Z|[+-]\d{2}(?::?\d{2})?)$',
    caseSensitive: false,
  ).hasMatch(value);
  final time = DateTime.tryParse(hasZone ? value : '${value}Z');
  if (time == null) throw FormatException('Invalid time: $value');
  return time.toUtc();
}

// Only GPX point fields are interpreted; extensions remain opaque XML.
List<RoutePoint> _parseGpx(String source) {
  final tokens = RegExp(
    r'''<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[[\s\S]*?\]\]>|<(?:"[^"]*"|'[^']*'|[^'">])*>|[^<]+''',
  );
  final stack = <String>[];
  final points = <RoutePoint>[];
  Map<String, String>? point;
  var pointDepth = 0;
  var fieldText = StringBuffer();
  var rootSeen = false;
  var offset = 0;
  for (final match in tokens.allMatches(source)) {
    if (match.start != offset) {
      throw const FormatException('Malformed GPX XML.');
    }
    offset = match.end;
    final token = match.group(0)!;
    if (token.startsWith('<!--') || token.startsWith('<?')) continue;
    if (token.startsWith('<![CDATA[')) {
      fieldText.write(token.substring(9, token.length - 3));
      continue;
    }
    if (!token.startsWith('<')) {
      if (stack.isEmpty && token.trim().isNotEmpty) {
        throw const FormatException('Text outside GPX root.');
      }
      fieldText.write(token);
      continue;
    }
    if (token.startsWith('<!')) {
      throw const FormatException(
        'GPX document types/entities are unsupported.',
      );
    }
    if (token.startsWith('</')) {
      final name = token.substring(2, token.length - 1).trim();
      if (stack.isEmpty || stack.last != name) {
        throw const FormatException('Mismatched GPX XML tags.');
      }
      final local = name.split(':').last;
      if (point != null &&
          stack.length == pointDepth + 1 &&
          (local == 'ele' || local == 'time')) {
        point[local] = _xmlText(fieldText.toString().trim());
      }
      if (point != null && stack.length == pointDepth) {
        points.add(_gpxPoint(point));
        point = null;
      }
      stack.removeLast();
      fieldText = StringBuffer();
      continue;
    }
    final opening = RegExp(r'^<([\w:.-]+)([\s\S]*?)(/?)>$').firstMatch(token);
    if (opening == null) throw const FormatException('Invalid GPX tag.');
    final name = opening.group(1)!;
    final local = name.split(':').last;
    if (stack.isEmpty) {
      if (rootSeen || local != 'gpx') {
        throw const FormatException('Expected one GPX root element.');
      }
      rootSeen = true;
    }
    final attributes = <String, String>{};
    var remainder = opening.group(2)!.trim();
    final attributePattern = RegExp(
      r'''^([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
    );
    while (remainder.isNotEmpty) {
      final attribute = attributePattern.firstMatch(remainder);
      if (attribute == null || attributes.containsKey(attribute.group(1))) {
        throw const FormatException('Invalid GPX attributes.');
      }
      attributes[attribute.group(1)!] = _xmlText(
        attribute.group(2) ?? attribute.group(3)!,
      );
      remainder = remainder.substring(attribute.end).trim();
    }
    stack.add(name);
    fieldText = StringBuffer();
    if (local == 'trkpt' || local == 'rtept' || local == 'wpt') {
      if (point != null) throw const FormatException('Nested GPX points.');
      point = attributes;
      pointDepth = stack.length;
    }
    if (opening.group(3) == '/') {
      if (point != null && pointDepth == stack.length) {
        points.add(_gpxPoint(point));
        point = null;
      }
      stack.removeLast();
    }
  }
  if (offset != source.length || stack.isNotEmpty || !rootSeen) {
    throw const FormatException('Incomplete GPX XML.');
  }
  return points;
}

String _xmlText(String text) =>
    text.replaceAllMapped(RegExp(r'&([^;]+);'), (match) {
      final entity = match.group(1)!;
      const predefined = {
        'amp': '&',
        'lt': '<',
        'gt': '>',
        'quot': '"',
        'apos': "'",
      };
      final replacement = predefined[entity];
      if (replacement != null) return replacement;
      final code = entity.startsWith('#x')
          ? int.tryParse(entity.substring(2), radix: 16)
          : entity.startsWith('#')
          ? int.tryParse(entity.substring(1))
          : null;
      if (code == null || code <= 0 || code > 0x10ffff) {
        throw const FormatException('Unsupported GPX entity.');
      }
      return String.fromCharCode(code);
    });

RoutePoint _gpxPoint(Map<String, String> fields) {
  double coordinate(String key) {
    final value = double.tryParse(fields[key] ?? '');
    if (value == null) throw FormatException('GPX point has invalid $key.');
    return value;
  }

  return RoutePoint(
    coordinate('lat'),
    coordinate('lon'),
    altitude: fields.containsKey('ele') ? coordinate('ele') : null,
    time: _time(fields['time']),
  );
}
