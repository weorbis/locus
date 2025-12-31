library;

import 'package:locus/src/models/models.dart';

abstract class TripStore {
  Future<void> save(TripState state);
  Future<TripState?> load();
  Future<void> clear();
}
