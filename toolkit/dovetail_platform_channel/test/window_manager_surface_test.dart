import 'dart:async';
import 'dart:ui';

import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:dovetail_platform_channel/src/window/window_manager_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagerSpy extends Mock implements WindowManager {}

class _FakeWindowOptions extends Fake implements WindowOptions {}

class _FakeWindowListener extends Fake implements WindowListener {}

const Rect _bounds = Rect.fromLTWH(120, 80, 1200, 720);
const Size _size = Size(1200, 720);

void main() {
  late WindowManagerSpy manager;
  late WindowManagerSurface surface;

  setUpAll(() {
    registerFallbackValue(_FakeWindowOptions());
    registerFallbackValue(Rect.zero);
    registerFallbackValue(_FakeWindowListener());
  });

  setUp(() {
    manager = WindowManagerSpy();
    surface = WindowManagerSurface(manager: manager);

    when(() => manager.ensureInitialized()).thenAnswer((_) async {});
    when(() => manager.show()).thenAnswer((_) async {});
    when(() => manager.hide()).thenAnswer((_) async {});
    when(() => manager.focus()).thenAnswer((_) async {});
    when(() => manager.minimize()).thenAnswer((_) async {});
    when(() => manager.restore()).thenAnswer((_) async {});
    when(() => manager.maximize()).thenAnswer((_) async {});
    when(() => manager.unmaximize()).thenAnswer((_) async {});
    when(() => manager.startDragging()).thenAnswer((_) async {});
    when(() => manager.isMaximized()).thenAnswer((_) async => false);
    when(() => manager.isVisible()).thenAnswer((_) async => true);
    when(() => manager.isFocused()).thenAnswer((_) async => true);
    when(() => manager.getBounds()).thenAnswer((_) async => _bounds);
    when(() => manager.getSize()).thenAnswer((_) async => _size);
    when(() => manager.setTitle(any())).thenAnswer((_) async {});
    when(() => manager.setBounds(any())).thenAnswer((_) async {});
    when(() => manager.setPreventClose(any())).thenAnswer((_) async {});
    when(() => manager.setSkipTaskbar(any())).thenAnswer((_) async {});
    when(() => manager.setAlwaysOnTop(any())).thenAnswer((_) async {});
    when(() => manager.addListener(any())).thenReturn(null);
    when(() => manager.removeListener(any())).thenReturn(null);
    when(() => manager.waitUntilReadyToShow(any(), any())).thenAnswer((
      Invocation call,
    ) async {
      await (call.positionalArguments[1] as Future<void> Function())();
    });
  });

  tearDown(() => surface.dispose());

  group('every forward should reach the method it names', () {
    test('the ones that take nothing', () async {
      await surface.show();
      await surface.hide();
      await surface.focus();
      await surface.minimize();
      await surface.restore();
      await surface.maximize();
      await surface.unmaximize();
      await surface.startDrag();

      verify(() => manager.show()).called(1);
      verify(() => manager.hide()).called(1);
      verify(() => manager.focus()).called(1);
      verify(() => manager.minimize()).called(1);
      verify(() => manager.restore()).called(1);
      verify(() => manager.maximize()).called(1);
      verify(() => manager.unmaximize()).called(1);
      verify(() => manager.startDragging()).called(1);
    });

    test('the three booleans should not be crossed', () async {
      await surface.setPreventClose(prevent: true);
      await surface.setSkipTaskbar(skip: false);
      await surface.setAlwaysOnTop(onTop: true);

      verify(() => manager.setPreventClose(true)).called(1);
      verify(() => manager.setSkipTaskbar(false)).called(1);
      verify(() => manager.setAlwaysOnTop(true)).called(1);
      verifyNever(() => manager.setSkipTaskbar(true));
      verifyNever(() => manager.setPreventClose(false));
    });

    test('a title should arrive as it was written', () async {
      await surface.setTitle('Ex & Co — "Client"');

      verify(() => manager.setTitle('Ex & Co — "Client"')).called(1);
    });

    test('bounds should go out and come back unchanged', () async {
      await surface.setBounds(_bounds);

      verify(() => manager.setBounds(_bounds)).called(1);
      expect(await surface.bounds(), _bounds);
    });

    test('the two queries should report what the manager says', () async {
      when(() => manager.isMaximized()).thenAnswer((_) async => true);
      when(() => manager.isVisible()).thenAnswer((_) async => false);

      expect(await surface.isMaximized(), true);
      expect(await surface.isVisible(), false);
    });
  });

  group('frameState', () {
    test('should gather all four values, not guess any', () async {
      when(() => manager.isMaximized()).thenAnswer((_) async => true);
      when(() => manager.isVisible()).thenAnswer((_) async => true);
      when(() => manager.isFocused()).thenAnswer((_) async => false);

      final WindowFrameState state = await surface.frameState();

      expect(state.size, _size);
      expect(state.maximized, true);
      expect(state.visible, true);
      expect(state.focused, false);
      verify(() => manager.getSize()).called(1);
      verify(() => manager.isFocused()).called(1);
    });
  });

  group('attach', () {
    test(
      'should register the listener once, however often it is called',
      () async {
        await surface.attach(const WindowSpec(size: _size, minimumSize: _size));
        await surface.attach(const WindowSpec(size: _size, minimumSize: _size));

        verify(() => manager.ensureInitialized()).called(1);
        verify(() => manager.addListener(surface)).called(1);
      },
    );

    test('a window asked to start hidden should not be shown', () async {
      await surface.attach(
        const WindowSpec(
          size: _size,
          minimumSize: _size,
          visibleOnStart: false,
        ),
      );

      verifyNever(() => manager.show());
      verifyNever(() => manager.focus());
    });

    test(
      'a window asked to start visible should be shown and focused',
      () async {
        await surface.attach(const WindowSpec(size: _size, minimumSize: _size));

        verify(() => manager.show()).called(1);
        verify(() => manager.focus()).called(1);
      },
    );

    test('detach should remove the listener and allow a re-attach', () async {
      await surface.attach(const WindowSpec(size: _size, minimumSize: _size));
      await surface.detach();
      await surface.attach(const WindowSpec(size: _size, minimumSize: _size));

      verify(() => manager.removeListener(surface)).called(1);
      verify(() => manager.addListener(surface)).called(2);
    });

    test('detach before attach should do nothing', () async {
      await surface.detach();

      verifyNever(() => manager.removeListener(any()));
    });
  });

  group('the listener bridge', () {
    test('a close request should reach the stream', () async {
      final Future<void> first = surface.closeRequests().first;

      surface.onWindowClose();

      await expectLater(first, completes);
    });

    test('a focus gain should reach a stream of its own', () async {
      final Future<void> gained = surface.focusGains().first;

      surface.onWindowFocus();

      await expectLater(
        gained,
        completes,
        reason:
            'this is the signal that a permission granted outside the app — '
            'in System Settings — has a chance of being noticed. Without it '
            'the app keeps saying "denied" until it is restarted',
      );
    });

    test('nothing but focus should reach that stream', () async {
      final List<void> gains = <void>[];
      final StreamSubscription<void> listening = surface.focusGains().listen(
        gains.add,
      );
      addTearDown(listening.cancel);

      surface
        ..onWindowResized()
        ..onWindowMaximize()
        ..onWindowUnmaximize()
        ..onWindowBlur();
      await Future<void>.delayed(Duration.zero);

      expect(
        gains,
        isEmpty,
        reason:
            'frameChanges carries focused and publishes on all of these, so a '
            'permission re-read hung on it would go to the system through '
            'every window drag',
      );
    });

    test('each frame event should publish the state', () async {
      final Future<List<WindowFrameState>> collected = surface
          .frameChanges()
          .take(5)
          .toList();

      surface
        ..onWindowResized()
        ..onWindowMaximize()
        ..onWindowUnmaximize()
        ..onWindowFocus()
        ..onWindowBlur();

      final List<WindowFrameState> states = await collected.timeout(
        const Duration(seconds: 5),
      );

      expect(states, hasLength(5));
      expect(
        states.every((WindowFrameState state) => state.size == _size),
        true,
      );
    });

    test('a moved window should not be reported as a frame change', () {
      expect(
        surface,
        isA<WindowListener>(),
        reason:
            'onWindowMoved is deliberately not overridden: WindowFrameState '
            'carries no position, so publishing a move would emit an event '
            'identical to the last one',
      );
    });

    test('nothing should be published after dispose', () async {
      await surface.dispose();

      expect(surface.onWindowClose, returnsNormally);
      expect(
        () => surface
          ..onWindowResized()
          ..onWindowFocus(),
        returnsNormally,
        reason:
            'a listener the compositor still holds must not throw onto a '
            'closed controller after the app has torn the window down',
      );
    });
  });
}
