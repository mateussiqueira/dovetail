import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:dovetail_platform_channel/src/notify/local_notifications_notifier.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class PluginSpy extends Mock implements FlutterLocalNotificationsPlugin {}

class _FakeSettings extends Fake implements InitializationSettings {}

void main() {
  late PluginSpy plugin;
  late LocalNotificationsNotifier notifier;

  setUpAll(() => registerFallbackValue(_FakeSettings()));

  setUp(() {
    plugin = PluginSpy();
    notifier = LocalNotificationsNotifier(
      applicationId: 'io.example.demo',
      displayName: 'Demo',
      guid: 'b0c2e6f4-2f3a-4c1e-9d5b-7a8c1e2f3a4b',
      plugin: plugin,
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
