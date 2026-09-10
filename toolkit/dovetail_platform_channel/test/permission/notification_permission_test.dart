import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _channel = MethodChannel(
  SystemNotificationPermission.channelName,
);

const SessionBus _withBus = SessionBus(
  environment: <String, String>{
    'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/tmp/fake-bus',
  },
  onLinux: true,
);

final SessionBus _withoutBus = SessionBus(
  environment: const <String, String>{},
  onLinux: true,
  exists: (String _) => false,
);

/// Um abridor que registra em vez de chamar o sistema.
final class _Opener implements ExternalOpener {
  final List<Uri> opened = <Uri>[];

  @override
  Future<bool> canOpenUrl(Uri url) async => true;

  @override
  Future<bool> openUrl(Uri url) async {
    opened.add(url);
    return true;
  }
}

SystemNotificationPermission _permissionOn(
  TargetPlatform platform, {
  ExternalOpener? opener,
  SessionBus? bus,
}) => SystemNotificationPermission(
  applicationId: 'io.example.demo',
  platform: platform,
  opener: opener ?? _Opener(),
  bus: bus ?? _withBus,
  // Sem símbolo nativo: este host não é Windows, e mesmo num Windows um
  // `flutter test` não carrega a DLL do plugin.
  windows: const WindowsNotificationSetting.absent(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> calls = <String>[];

  void macOSAnswers(int code) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
          calls.add(call.method);
          return code;
        });
  }

  setUp(calls.clear);

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  group('macOS', () {
    test('state should read the native code without asking anyone', () async {
      macOSAnswers(3);

      expect(
        await _permissionOn(TargetPlatform.macOS).state(),
        PermissionState.denied,
      );
      expect(
        calls,
        <String>['state'],
        reason:
            'state must never reach requestAuthorization: a probe that opens '
            'the dialog turns every screen that displays the current state '
            'into a prompt',
      );
    });

    test('request should call the method that opens the dialog', () async {
      macOSAnswers(2);

      expect(
        await _permissionOn(TargetPlatform.macOS).request(),
        PermissionState.granted,
      );
      expect(calls, <String>['request']);
    });

    test('a missing plugin should answer unsupported, not throw', () async {
      // Nenhum handler registrado: é o que um app construído antes deste canal
      // encontra, e é todo teste de widget.
      expect(
        await _permissionOn(TargetPlatform.macOS).state(),
        PermissionState.unsupported,
        reason:
            'a permission read that throws forces every screen to wrap the '
            'call in a try, and the first one that forgets breaks on the '
            'machine of whoever installed it',
      );
    });

    test('a native that answers nothing should be unsupported', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (MethodCall call) async => null);

      expect(
        await _permissionOn(TargetPlatform.macOS).state(),
        PermissionState.unsupported,
      );
    });
  });

  group('Windows', () {
    test('without the native symbol should answer unsupported', () async {
      expect(
        await _permissionOn(TargetPlatform.windows).state(),
        PermissionState.unsupported,
        reason:
            'an app built before this symbol existed still notifies — Windows '
            'has no prompt to miss — and unsupported is the state that keeps '
            'delivering while admitting the registry was not read',
      );
    });

    test(
      'request should be the same read, because there is no dialog',
      () async {
        final SystemNotificationPermission sut = _permissionOn(
          TargetPlatform.windows,
        );

        expect(await sut.request(), await sut.state());
      },
    );
  });

  group('Linux', () {
    test('a reachable session bus should be granted', () async {
      expect(
        await _permissionOn(TargetPlatform.linux, bus: _withBus).state(),
        PermissionState.granted,
        reason:
            'nobody is ever asked on Linux: the desktop notification service '
            'serves whoever reaches it on the bus',
      );
    });

    test('no session bus should be unsupported, not denied', () async {
      expect(
        await _permissionOn(TargetPlatform.linux, bus: _withoutBus).state(),
        PermissionState.unsupported,
        reason:
            'denied would send the user to a settings pane to allow something '
            'that no service on this session offers. A container and an ssh '
            'login look exactly like this',
      );
    });
  });

  group('openSettings', () {
    test('macOS should open the notifications pane', () async {
      final _Opener opener = _Opener();

      expect(
        await _permissionOn(
          TargetPlatform.macOS,
          opener: opener,
        ).openSettings(),
        true,
      );
      expect(
        opener.opened.single.toString(),
        'x-apple.systempreferences:com.apple.preference.notifications',
        reason:
            'the pane identifier is the contract with System Settings; a typo '
            'here opens the top of Settings and leaves the person hunting',
      );
    });

    test('Windows should open the notifications page', () async {
      final _Opener opener = _Opener();

      expect(
        await _permissionOn(
          TargetPlatform.windows,
          opener: opener,
        ).openSettings(),
        true,
      );
      expect(opener.opened.single.toString(), 'ms-settings:notifications');
    });

    test('Linux should refuse without opening anything', () async {
      final _Opener opener = _Opener();

      expect(
        await _permissionOn(
          TargetPlatform.linux,
          opener: opener,
        ).openSettings(),
        false,
        reason:
            'there is no URL that reaches the notification settings of GNOME, '
            'KDE and XFCE alike. Guessing one opens the wrong pane, or the '
            'file manager, which is worse than not offering the button',
      );
      expect(opener.opened, isEmpty);
    });
  });

  group('a platform that is not desktop', () {
    test('should answer unsupported and no settings pane', () async {
      final _Opener opener = _Opener();
      final SystemNotificationPermission sut = _permissionOn(
        TargetPlatform.android,
        opener: opener,
      );

      expect(await sut.state(), PermissionState.unsupported);
      expect(await sut.request(), PermissionState.unsupported);
      expect(await sut.openSettings(), false);
      expect(opener.opened, isEmpty);
    });
  });
}
