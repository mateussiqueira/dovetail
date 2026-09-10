import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:dovetail_platform_channel/src/notify/local_notifications_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class PluginSpy extends Mock implements FlutterLocalNotificationsPlugin {}

class _FakeSettings extends Fake implements InitializationSettings {}

/// Uma permissão que responde o que o teste mandar, e conta as leituras.
final class _Permission implements NotificationPermission {
  _Permission(this.answer);

  PermissionState answer;
  int reads = 0;

  @override
  Future<PermissionState> state() async {
    reads++;
    return answer;
  }

  @override
  Future<PermissionState> request() async => answer;

  @override
  Future<bool> openSettings() async => false;
}

void main() {
  late PluginSpy plugin;
  late _Permission permission;
  late LocalNotificationsNotifier notifier;

  setUpAll(() => registerFallbackValue(_FakeSettings()));

  // A plataforma é declarada, e não herdada do host: o booleano que
  // `initialize` devolve quer dizer coisas diferentes em cada uma, e um teste
  // que dependesse do sistema onde roda provaria coisas diferentes no Mac de
  // quem escreve e no runner de Linux.
  LocalNotificationsNotifier notifierOn(TargetPlatform platform) =>
      LocalNotificationsNotifier(
        applicationId: 'io.example.demo',
        displayName: 'Demo',
        guid: 'b0c2e6f4-2f3a-4c1e-9d5b-7a8c1e2f3a4b',
        plugin: plugin,
        permission: permission,
        platform: platform,
        // Injetamos um SessionBus alcançável para que o host (Linux sem D-Bus
        // ou macOS) nunca decida o resultado: o plugin mockado é quem controla
        // se initialize aceita ou recusa a sessão.
        bus: const SessionBus(
          environment: <String, String>{
            'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/tmp/fake-bus',
          },
          onLinux: true,
        ),
      );

  setUp(() {
    plugin = PluginSpy();
    permission = _Permission(PermissionState.granted);
    notifier = notifierOn(TargetPlatform.macOS);

    when(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async {});
    when(() => plugin.cancel(id: any(named: 'id'))).thenAnswer((_) async {});
    when(() => plugin.cancelAll()).thenAnswer((_) async {});
  });

  void initialiseSucceeds() => when(
    () => plugin.initialize(settings: any(named: 'settings')),
  ).thenAnswer((_) async => true);

  void initialiseFails(Object error) => when(
    () => plugin.initialize(settings: any(named: 'settings')),
  ).thenThrow(error);

  void initialiseAnswers(bool? answer) => when(
    () => plugin.initialize(settings: any(named: 'settings')),
  ).thenAnswer((_) async => answer);

  group('attaching', () {
    test('a session that accepts it should report available', () async {
      initialiseSucceeds();

      expect(await notifier.attach(), true);
      expect(notifier.isAvailable, true);
      expect(notifier.unavailableBecause, isNull);
    });

    test('a session that refuses it should not throw', () async {
      initialiseFails(StateError('no notification daemon on this session'));

      expect(
        await notifier.attach(),
        false,
        reason:
            'ensureInitialized awaited this unconditionally, so a Linux '
            'session with no daemon took the whole application down at boot '
            'over a feature that shows toasts',
      );
      expect(notifier.isAvailable, false);
      expect(notifier.unavailableBecause, contains('no notification daemon'));
    });

    test('attaching twice should initialise once', () async {
      initialiseSucceeds();

      await notifier.attach();
      await notifier.attach();

      verify(
        () => plugin.initialize(settings: any(named: 'settings')),
      ).called(1);
    });

    test('a second attempt after a failure should be allowed', () async {
      initialiseFails(StateError('the bus was not up yet'));
      expect(await notifier.attach(), false);

      initialiseSucceeds();
      expect(await notifier.attach(), true);
      expect(notifier.unavailableBecause, isNull);
    });

    test('should not ask anyone for permission on the way in', () async {
      initialiseSucceeds();

      await notifier.attach();

      final InitializationSettings settings =
          verify(
                () =>
                    plugin.initialize(settings: captureAny(named: 'settings')),
              ).captured.single
              as InitializationSettings;
      final DarwinInitializationSettings darwin = settings.macOS!;

      expect(darwin.requestAlertPermission, false);
      expect(darwin.requestSoundPermission, false);
      expect(
        darwin.requestBadgePermission,
        false,
        reason:
            'these three default to TRUE in the plugin, so the macOS dialog '
            'used to appear at boot as a side effect of initialising — before '
            'the person could have any idea what the app wants to notify '
            'about. A "no" there is final: the system never shows the dialog '
            'again',
      );
    });

    test('a macOS false should not be read as a refusal', () async {
      initialiseAnswers(false);

      expect(
        await notifierOn(TargetPlatform.macOS).attach(),
        true,
        reason:
            'with the three requests off, the plugin answers false without '
            'talking to anyone — it is the verdict of a permission request '
            'that was never made. Reading it as failure would leave every '
            'macOS app unable to notify',
      );
    });

    test('a Windows false should be read as a refusal', () async {
      initialiseAnswers(false);
      final LocalNotificationsNotifier windows = notifierOn(
        TargetPlatform.windows,
      );

      expect(
        await windows.attach(),
        false,
        reason:
            'the same boolean on Windows is the return of the native init, '
            'and false there is a genuine failure. Discarding it was how an '
            'unusable notifier reported itself available',
      );
      expect(windows.unavailableBecause, contains('answering false'));
    });

    test('an answer of null should name the platform that had none', () async {
      initialiseAnswers(null);
      final LocalNotificationsNotifier linux = notifierOn(TargetPlatform.linux);

      expect(await linux.attach(), false);
      expect(linux.unavailableBecause, contains('linux'));
    });
  });

  group('the permission to show', () {
    setUp(() async {
      initialiseSucceeds();
      await notifier.attach();
    });

    test('a denied permission should refuse, and point at settings', () async {
      permission.answer = PermissionState.denied;

      await expectLater(
        notifier.show(const SystemNotice(id: 1, title: 't', body: 'b')),
        throwsA(
          isA<NotificationPermissionRefused>()
              .having(
                (NotificationPermissionRefused failure) => failure.state,
                'state',
                PermissionState.denied,
              )
              .having(
                (NotificationPermissionRefused failure) => '$failure',
                'message',
                contains('openSettings'),
              ),
        ),
        reason:
            'the plugin shows nothing on a denied permission and reports no '
            'error, so the notice vanishes and nobody learns why',
      );
      verifyNever(
        () => plugin.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      );
    });

    test('a permission never asked should say to ask, not to open '
        'settings', () async {
      permission.answer = PermissionState.notDetermined;

      await expectLater(
        notifier.show(const SystemNotice(id: 1, title: 't', body: 'b')),
        throwsA(
          isA<NotificationPermissionRefused>().having(
            (NotificationPermissionRefused failure) => '$failure',
            'message',
            contains('request()'),
          ),
        ),
        reason:
            'these are opposite journeys: here the dialog still works, and a '
            'screen that sent the person to System Settings instead would be '
            'asking them to fix something they were never asked about',
      );
    });

    test('a restricted permission should blame the policy', () async {
      permission.answer = PermissionState.restricted;

      await expectLater(
        notifier.show(const SystemNotice(id: 2, title: 't', body: 'b')),
        throwsA(
          isA<NotificationPermissionRefused>().having(
            (NotificationPermissionRefused failure) => '$failure',
            'message',
            contains('policy'),
          ),
        ),
      );
    });

    test('a platform with no permission model should still show', () async {
      permission.answer = PermissionState.unsupported;

      await notifier.show(const SystemNotice(id: 3, title: 't', body: 'b'));

      verify(() => plugin.show(id: 3, title: 't', body: 'b')).called(1);
    });

    test('should be read again at every notice, not cached at attach', () async {
      await notifier.show(const SystemNotice(id: 4, title: 't', body: 'b'));
      permission.answer = PermissionState.denied;

      await expectLater(
        notifier.show(const SystemNotice(id: 5, title: 't', body: 'b')),
        throwsA(isA<NotificationPermissionRefused>()),
        reason:
            'the person can turn the app off in Settings while it is running, '
            'and a verdict cached at boot would keep saying everything is '
            'fine while nothing arrives',
      );
      expect(permission.reads, 2);
    });

    test('cancelling should not need permission', () async {
      permission.answer = PermissionState.denied;

      await notifier.cancel(4);
      await notifier.cancelAll();

      verify(() => plugin.cancel(id: 4)).called(1);
      verify(() => plugin.cancelAll()).called(1);
    });
  });

  group('showing', () {
    test('an available notifier should pass the notice through', () async {
      initialiseSucceeds();
      await notifier.attach();

      await notifier.show(
        const SystemNotice(id: 7, title: 'Connected', body: 'br-1'),
      );

      verify(
        () => plugin.show(id: 7, title: 'Connected', body: 'br-1'),
      ).called(1);
    });

    test('an unavailable notifier should refuse with the reason', () async {
      initialiseFails(StateError('no notification daemon'));
      await notifier.attach();

      await expectLater(
        notifier.show(const SystemNotice(id: 1, title: 't', body: 'b')),
        throwsA(
          isA<NotificationsUnavailable>().having(
            (NotificationsUnavailable failure) => failure.because,
            'because',
            contains('no notification daemon'),
          ),
        ),
        reason:
            'showing nothing in silence means a user never sees the notice '
            'and nobody learns why',
      );
      verifyNever(
        () => plugin.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      );
    });

    test(
      'a notifier never attached should say that, not blame the session',
      () async {
        await expectLater(
          notifier.show(const SystemNotice(id: 1, title: 't', body: 'b')),
          throwsA(
            isA<NotificationsUnavailable>().having(
              (NotificationsUnavailable failure) => failure.because,
              'because',
              contains('attach has not been called'),
            ),
          ),
        );
      },
    );

    test('cancel and cancelAll should refuse the same way', () async {
      await expectLater(
        notifier.cancel(1),
        throwsA(isA<NotificationsUnavailable>()),
      );
      await expectLater(
        notifier.cancelAll(),
        throwsA(isA<NotificationsUnavailable>()),
      );
    });

    test('cancel should reach the plugin once available', () async {
      initialiseSucceeds();
      await notifier.attach();

      await notifier.cancel(9);
      await notifier.cancelAll();

      verify(() => plugin.cancel(id: 9)).called(1);
      verify(() => plugin.cancelAll()).called(1);
    });
  });

  group('a session with no bus', () {
    LocalNotificationsNotifier withoutBus() => LocalNotificationsNotifier(
      applicationId: 'io.example.demo',
      displayName: 'Demo',
      guid: 'b0c2e6f4-2f3a-4c1e-9d5b-7a8c1e2f3a4b',
      plugin: plugin,
      permission: permission,
      platform: TargetPlatform.linux,
      bus: SessionBus(
        environment: const <String, String>{},
        onLinux: true,
        exists: (String _) => false,
      ),
    );

    test('should not be asked to initialize at all', () async {
      initialiseSucceeds();

      expect(await withoutBus().attach(), false);
      verifyNever(() => plugin.initialize(settings: any(named: 'settings')));
    });

    test('should say which session it is, not which call failed', () async {
      initialiseSucceeds();
      final LocalNotificationsNotifier sut = withoutBus();

      await sut.attach();

      expect(sut.unavailableBecause, contains('no D-Bus session bus'));
      expect(
        sut.isAvailable,
        false,
        reason:
            'the plugin registers a D-Bus signal listener inside initialize, '
            'and its failure arrives asynchronously, so an await that returns '
            'without throwing is not proof the service is there',
      );
    });
  });
}
