import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dovetail_rust_core/dovetail_rust_core.dart';

void main() {
  group('the refusal has to arrive through the Future', () {
    test(
      'an unsupported platform should be catchable, not thrown at the call',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        final RustBridge bridge = RustBridge(initializer: () async {});

        Object? caught;
        await bridge.ensureInitialized().catchError((Object error) {
          caught = error;
        });

        expect(
          caught,
          isA<UnsupportedPlatformException>(),
          reason:
              'the signature promises a Future, and a synchronous throw escapes '
              'catchError and Future.wait entirely',
        );
      },
    );

    test('Future.wait should contain the refusal', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final RustBridge bridge = RustBridge(initializer: () async {});

      await expectLater(
        Future.wait(<Future<void>>[
          bridge.ensureInitialized(),
          Future<void>.value(),
        ]),
        throwsA(isA<UnsupportedPlatformException>()),
      );
    });

    test('a failed initializer should let the next attempt through', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      int attempts = 0;
      final RustBridge bridge = RustBridge(
        initializer: () async {
          attempts++;
          if (attempts == 1) {
            throw StateError('the library was not there yet');
          }
        },
      );

      await expectLater(bridge.ensureInitialized(), throwsA(isA<StateError>()));
      await expectLater(bridge.ensureInitialized(), completes);
      expect(attempts, 2);
    });

    test('a success should not be re-run', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      int attempts = 0;
      final RustBridge bridge = RustBridge(initializer: () async => attempts++);

      await bridge.ensureInitialized();
      await bridge.ensureInitialized();
      expect(attempts, 1);
    });
  });

  late int initCalls;
  late RustBridge sut;

  setUp(() {
    initCalls = 0;
    sut = RustBridge(initializer: () async => initCalls++);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('isSupported should be true on every desktop platform', () {
    for (final TargetPlatform platform in desktopPlatforms) {
      debugDefaultTargetPlatformOverride = platform;

      expect(sut.isSupported, true, reason: platform.name);
    }
  });

  test('isSupported should be false on mobile by default', () {
    for (final TargetPlatform platform in mobilePlatforms) {
      debugDefaultTargetPlatformOverride = platform;

      expect(sut.isSupported, false, reason: platform.name);
    }
  });

  test('isSupported should follow a caller that declares mobile support', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final RustBridge mobile = RustBridge(
      initializer: () async {},
      supportedPlatforms: mobilePlatforms,
    );

    expect(mobile.isSupported, true);
    expect(sut.isSupported, false);
  });

  test('ensureInitialized should refuse an unsupported platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    expect(sut.ensureInitialized, throwsA(isA<UnsupportedPlatformException>()));
  });

  test('ensureInitialized should refuse before calling the initializer', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(sut.ensureInitialized, throwsA(isA<UnsupportedPlatformException>()));
    expect(initCalls, 0);
  });

  test('ensureInitialized should call the initializer once', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await sut.ensureInitialized();
    await sut.ensureInitialized();
    await sut.ensureInitialized();

    expect(initCalls, 1);
  });

  test('ensureInitialized should allow a retry after a failure', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    int attempts = 0;
    final RustBridge failing = RustBridge(
      initializer: () async {
        attempts++;
        if (attempts == 1) {
          throw StateError('library missing');
        }
      },
    );

    await expectLater(failing.ensureInitialized(), throwsStateError);
    await failing.ensureInitialized();

    expect(attempts, 2);
  });

  test(
    'UnsupportedPlatformException should name the platform and the guard',
    () {
      const sut = UnsupportedPlatformException.platform(TargetPlatform.android);

      expect(sut.toString(), contains('android'));
      expect(sut.toString(), contains('isSupported'));
    },
  );

  test(
    'UnsupportedPlatformException should describe web without a platform',
    () {
      const sut = UnsupportedPlatformException.web();

      expect(sut.platform, null);
      expect(sut.toString(), contains('web'));
    },
  );
}
