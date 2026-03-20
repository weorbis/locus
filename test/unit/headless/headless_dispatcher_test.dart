import 'dart:ui' show PluginUtilities;

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/core/locus_headless.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'headlessDispatcher is a top-level function with a valid callback handle',
      () {
    // executeDartCallback resolves functions via Dart_GetField(library, name)
    // which only finds top-level functions. If headlessDispatcher were a static
    // method on a class, the native lookup would silently fail and the headless
    // Dart isolate would never start.
    final handle = PluginUtilities.getCallbackHandle(headlessDispatcher);
    expect(handle, isNotNull, reason: 'headlessDispatcher must be resolvable');
  });
}
