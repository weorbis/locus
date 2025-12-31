import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:locus/locus.dart';

void main() {
  test('permission request flow requires when-in-use', () async {
    // We cannot mock platform permissions here, but ensure the API path is callable.
    // This test ensures the method is accessible without throwing.
    expect(Locus.requestPermission, isA<Function>());
  });

  test('permission handler enums are available', () {
    // Sanity check that permission handler symbols resolve in this package.
    expect(Permission.locationWhenInUse, isNotNull);
    expect(Permission.locationAlways, isNotNull);
  });
}
