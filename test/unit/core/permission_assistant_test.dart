import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus/src/core/permission_assistant.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var foregroundStatus = PermissionStatus.granted;
  var backgroundStatus = PermissionStatus.permanentlyDenied;

  setUp(() {
    calls.clear();
    foregroundStatus = PermissionStatus.granted;
    backgroundStatus = PermissionStatus.permanentlyDenied;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'checkPermissionStatus') {
        // A fresh request result is authoritative over a stale status query.
        return PermissionStatus.denied.index;
      }
      if (call.method != 'requestPermissions') {
        throw StateError('Unexpected method: ${call.method}');
      }
      final Object? arguments = call.arguments;
      if (arguments is! List<Object?> || arguments.length != 1) {
        throw StateError('Expected one permission per request');
      }
      final permission = arguments.single;
      if (permission == Permission.locationWhenInUse.value) {
        return <int, int>{
          Permission.locationWhenInUse.value: foregroundStatus.index,
        };
      }
      if (permission == Permission.locationAlways.value) {
        return <int, int>{
          Permission.locationAlways.value: backgroundStatus.index,
        };
      }
      throw StateError('Unexpected permission: $permission');
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'permanent background denial opens settings from the request result',
    () async {
      var settingsOpened = 0;
      final granted = await PermissionAssistant.requestBackgroundWorkflow(
        delegate: PermissionFlowDelegate(
          onOpenSettings: () async {
            settingsOpened++;
          },
        ),
      );
      expect(granted, isFalse);
      expect(settingsOpened, 1);
      expect(calls.map((call) => call.method), [
        'requestPermissions',
        'requestPermissions',
      ]);
      expect(calls.map((call) => call.arguments), [
        [Permission.locationWhenInUse.value],
        [Permission.locationAlways.value],
      ]);
    },
  );

  test(
    'ordinary background denial does not open settings or recheck status',
    () async {
      backgroundStatus = PermissionStatus.denied;
      var settingsOpened = false;
      expect(
        await PermissionAssistant.requestBackgroundWorkflow(
          delegate: PermissionFlowDelegate(
            onOpenSettings: () async {
              settingsOpened = true;
            },
          ),
        ),
        isFalse,
      );
      expect(settingsOpened, isFalse);
      expect(calls.map((call) => call.method), [
        'requestPermissions',
        'requestPermissions',
      ]);
    },
  );

  test(
    'foreground denial stops before requesting background permission',
    () async {
      foregroundStatus = PermissionStatus.denied;
      var settingsOpened = false;
      expect(
        await PermissionAssistant.requestBackgroundWorkflow(
          delegate: PermissionFlowDelegate(
            onOpenSettings: () async {
              settingsOpened = true;
            },
          ),
        ),
        isFalse,
      );
      expect(settingsOpened, isFalse);
      expect(calls.map((call) => call.arguments), [
        [Permission.locationWhenInUse.value],
      ]);
    },
  );

  test('settings callback failures propagate to the caller', () async {
    final failure = StateError('settings delegate failed');
    await expectLater(
      PermissionAssistant.requestBackgroundWorkflow(
        delegate: PermissionFlowDelegate(
          onOpenSettings: () async {
            throw failure;
          },
        ),
      ),
      throwsA(same(failure)),
    );
  });
}
