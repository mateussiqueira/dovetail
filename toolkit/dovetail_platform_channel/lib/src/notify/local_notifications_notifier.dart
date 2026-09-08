import 'dart:async';
import 'dart:io';

import 'package:dovetail_platform_channel/src/notify/notifications_unavailable.dart';
import 'package:dovetail_platform_channel/src/notify/session_bus.dart';
import 'package:dovetail_platform_channel/src/notify/system_notice.dart';
import 'package:dovetail_platform_channel/src/notify/system_notifier.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final class LocalNotificationsNotifier implements SystemNotifier {
  LocalNotificationsNotifier({
    required this.applicationId,
    required this.displayName,
    required this.guid,
    FlutterLocalNotificationsPlugin? plugin,
    SessionBus? bus,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _bus =
           bus ??
           SessionBus(
             environment: Platform.environment,
             onLinux: Platform.isLinux,
           );

  final String applicationId;
  final String displayName;
  final String guid;

  final FlutterLocalNotificationsPlugin _plugin;
  final SessionBus _bus;

  bool _initialized = false;
  String? _unavailableBecause;

  bool get isAvailable => _initialized;

  String? get unavailableBecause => _unavailableBecause;

  Future<bool> attach() async {
    if (_initialized) {
      return true;
    }
    if (!_bus.reachable) {
      _unavailableBecause = _bus.absentBecause;
      return false;
    }

    final Completer<void> settled = Completer<void>();
    runZonedGuarded(() async {
      try {
        await _plugin.initialize(settings: _settings);
        _initialized = true;
        _unavailableBecause = null;
      } on Object catch (error) {
        _unavailableBecause = '$error';
      }
      if (!settled.isCompleted) {
        settled.complete();
      }
    }, _swallow);
    await settled.future;
    return _initialized;
  }

  InitializationSettings get _settings => InitializationSettings(
    macOS: const DarwinInitializationSettings(),
    linux: LinuxInitializationSettings(defaultActionName: displayName),
    windows: WindowsInitializationSettings(
      appName: displayName,
      appUserModelId: applicationId,
      guid: guid,
    ),
  );

  void _swallow(Object error, StackTrace trace) {
    _unavailableBecause ??= '$error';
    stderr.writeln(
      'the notification service failed after it was reached, and the app is '
      'carrying on without notifications: $error',
    );
  }

  @override
  Future<void> show(SystemNotice notice) async {
    _refuseIfUnavailable();
    await _plugin.show(id: notice.id, title: notice.title, body: notice.body);
  }

  @override
  Future<void> cancel(int id) async {
    _refuseIfUnavailable();
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    _refuseIfUnavailable();
    await _plugin.cancelAll();
  }

  void _refuseIfUnavailable() {
    if (_initialized) {
      return;
    }
    throw NotificationsUnavailable(
      _unavailableBecause ?? 'attach has not been called',
    );
  }
}
