import 'dart:math';

// --- Mocks ---

class Coords {
  final double latitude;
  final double longitude;
  final double accuracy;
  const Coords(
      {required this.latitude,
      required this.longitude,
      required this.accuracy});
}

class RoutePoint {
  final double latitude;
  final double longitude;
  const RoutePoint({required this.latitude, required this.longitude});
}

class LocationUtils {
  static double calculateDistance(Coords a, Coords b) {
    const p = 0.017453292519943295;
    final c = cos;
    final aVal = 0.5 -
        c((b.latitude - a.latitude) * p) / 2 +
        c(a.latitude * p) *
            c(b.latitude * p) *
            (1 - c((b.longitude - a.longitude) * p)) /
            2;
    return 12742 * asin(sqrt(aVal)) * 1000;
  }
}

// --- Original Implementation ---

class LegacyVectorMath {
  double distanceToSegmentMeters(
    Coords point,
    RoutePoint start,
    RoutePoint end,
  ) {
    final startCoords = Coords(
      latitude: start.latitude,
      longitude: start.longitude,
      accuracy: 0,
    );
    final endCoords = Coords(
      latitude: end.latitude,
      longitude: end.longitude,
      accuracy: 0,
    );
    final pointCoords = point;

    final startVec = _toVector(startCoords);
    final endVec = _toVector(endCoords);
    final pointVec = _toVector(pointCoords);

    final segment = _vectorSubtract(endVec, startVec);
    final lengthSquared = _dot(segment, segment);
    if (lengthSquared == 0) {
      return LocationUtils.calculateDistance(pointCoords, startCoords);
    }
    final t =
        _dot(_vectorSubtract(pointVec, startVec), segment) / lengthSquared;
    final clampedT = t.clamp(0.0, 1.0);
    final projection = _vectorAdd(startVec, _vectorScale(segment, clampedT));
    final projectedCoords = _fromVector(projection);
    return LocationUtils.calculateDistance(pointCoords, projectedCoords);
  }

  List<double> _toVector(Coords coords) {
    final lat = coords.latitude * pi / 180.0;
    final lng = coords.longitude * pi / 180.0;
    return [cos(lat) * cos(lng), cos(lat) * sin(lng), sin(lat)];
  }

  Coords _fromVector(List<double> vector) {
    final lat =
        atan2(vector[2], sqrt(vector[0] * vector[0] + vector[1] * vector[1]));
    final lng = atan2(vector[1], vector[0]);
    return Coords(
      latitude: lat * 180.0 / pi,
      longitude: lng * 180.0 / pi,
      accuracy: 0,
    );
  }

  List<double> _vectorAdd(List<double> a, List<double> b) {
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  }

  List<double> _vectorSubtract(List<double> a, List<double> b) {
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  }

  List<double> _vectorScale(List<double> a, double scale) {
    return [a[0] * scale, a[1] * scale, a[2] * scale];
  }

  double _dot(List<double> a, List<double> b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  }
}

// --- Optimized Implementation ---

class OptimizedVectorMath {
  double distanceToSegmentMeters(
    Coords point,
    RoutePoint start,
    RoutePoint end,
  ) {
    // 1. Convert start to vector
    final startLat = start.latitude * pi / 180.0;
    final startLng = start.longitude * pi / 180.0;
    final sx = cos(startLat) * cos(startLng);
    final sy = cos(startLat) * sin(startLng);
    final sz = sin(startLat);

    // 2. Convert end to vector
    final endLat = end.latitude * pi / 180.0;
    final endLng = end.longitude * pi / 180.0;
    final ex = cos(endLat) * cos(endLng);
    final ey = cos(endLat) * sin(endLng);
    final ez = sin(endLat);

    // 3. Convert point to vector
    final pointLat = point.latitude * pi / 180.0;
    final pointLng = point.longitude * pi / 180.0;
    final px = cos(pointLat) * cos(pointLng);
    final py = cos(pointLat) * sin(pointLng);
    final pz = sin(pointLat);

    // 4. segment = endVec - startVec
    final segX = ex - sx;
    final segY = ey - sy;
    final segZ = ez - sz;

    // 5. lengthSquared = dot(segment, segment)
    final lengthSquared = segX * segX + segY * segY + segZ * segZ;

    if (lengthSquared == 0) {
      return LocationUtils.calculateDistance(
        point,
        Coords(
            latitude: start.latitude, longitude: start.longitude, accuracy: 0),
      );
    }

    // 6. t = dot(pointVec - startVec, segment) / lengthSquared
    final pointMinusStartX = px - sx;
    final pointMinusStartY = py - sy;
    final pointMinusStartZ = pz - sz;

    final t = (pointMinusStartX * segX +
            pointMinusStartY * segY +
            pointMinusStartZ * segZ) /
        lengthSquared;

    final clampedT = t.clamp(0.0, 1.0);

    // 7. projection = startVec + segment * clampedT
    final projX = sx + segX * clampedT;
    final projY = sy + segY * clampedT;
    final projZ = sz + segZ * clampedT;

    // 8. projectedCoords = _fromVector(projection)
    final projLatRad = atan2(projZ, sqrt(projX * projX + projY * projY));
    final projLngRad = atan2(projY, projX);

    final projectedCoords = Coords(
      latitude: projLatRad * 180.0 / pi,
      longitude: projLngRad * 180.0 / pi,
      accuracy: 0,
    );

    return LocationUtils.calculateDistance(point, projectedCoords);
  }
}

void main() {
  final legacy = LegacyVectorMath();
  final optimized = OptimizedVectorMath();

  final point = Coords(latitude: 37.7749, longitude: -122.4194, accuracy: 5);
  final start = RoutePoint(latitude: 37.7740, longitude: -122.4200);
  final end = RoutePoint(latitude: 37.7760, longitude: -122.4190);

  // Warmup
  print("Warming up...");
  for (var i = 0; i < 10000; i++) {
    legacy.distanceToSegmentMeters(point, start, end);
    optimized.distanceToSegmentMeters(point, start, end);
  }

  final iterations = 1000000;

  // Measure Legacy
  final stopwatch1 = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    legacy.distanceToSegmentMeters(point, start, end);
  }
  stopwatch1.stop();
  print("Legacy: ${stopwatch1.elapsedMilliseconds}ms");

  // Measure Optimized
  final stopwatch2 = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    optimized.distanceToSegmentMeters(point, start, end);
  }
  stopwatch2.stop();
  print("Optimized: ${stopwatch2.elapsedMilliseconds}ms");

  final improvement =
      stopwatch1.elapsedMilliseconds - stopwatch2.elapsedMilliseconds;
  final percent =
      (improvement / stopwatch1.elapsedMilliseconds * 100).toStringAsFixed(1);
  print("Improvement: ${improvement}ms ($percent%)");
}
