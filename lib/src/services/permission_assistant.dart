import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import 'package:locus/src/config/geolocation_config.dart';
import 'package:locus/src/config/permission_rationale.dart';
import 'package:locus/src/services/permission_service.dart';

/// Delegate for permission workflow UI steps.
class PermissionFlowDelegate {
  final Future<bool> Function(PermissionRationale rationale)? onShowRationale;
  final Future<void> Function()? onOpenSettings;

  const PermissionFlowDelegate({
    this.onShowRationale,
    this.onOpenSettings,
  });
}

/// Guided permission workflow with optional UI delegate.
class PermissionAssistant {
  /// Requests the background permission workflow with rationale hooks.
  static Future<bool> requestBackgroundWorkflow({
    PermissionFlowDelegate? delegate,
    Config? config,
  }) async {
    final whenInUse = await PermissionService.requestWhenInUse();
    if (!whenInUse.isGranted) {
      return false;
    }

    final rationale = config?.backgroundPermissionRationale;
    if (rationale != null && delegate?.onShowRationale != null) {
      final proceed = await delegate!.onShowRationale!(rationale);
      if (!proceed) {
        return false;
      }
    }

    final always = await PermissionService.requestAlways();
    if (!always.isGranted) {
      if (delegate?.onOpenSettings != null &&
          await Permission.locationAlways.isPermanentlyDenied) {
        await delegate!.onOpenSettings!();
      }
      return false;
    }

    final activity = await PermissionService.requestActivity();
    if (!activity.isGranted) {
      return false;
    }

    if (Platform.isAndroid) {
      final notification = await PermissionService.requestNotification();
      if (!notification.isGranted) {
        return false;
      }
    }

    return true;
  }
}
