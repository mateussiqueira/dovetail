import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const Rect _screen = Rect.fromLTWH(0, 25, 1512, 957);
const Size _panel = Size(360, 480);

final class _FakeDisplays implements DisplayProbe {
  const _FakeDisplays();

  @override
  Future<Offset> cursorPoint() async => const Offset(1300, 25);

  @override
  Future<Rect> workAreaForPoint(Offset point) async => _screen;

  @override
  Future<List<Rect>> workAreas() async => const <Rect>[_screen];
}

final class _Window implements WindowSurface {
  _Window({this.failOnHide = false});

  final bool failOnHide;
  Rect bounds_ = Rect.zero;
  bool visible = false;
  final StreamController<WindowFrameState> _frames =
      StreamController<WindowFrameState>.broadcast();

  void blur() => _frames.add(
    const WindowFrameState(
      size: Size(360, 480),
      maximized: false,
      visible: true,
      focused: false,
    ),
  );

  @override
  Future<void> hide() async {
    if (failOnHide) {
      throw StateError('the compositor refused to hide the window');
    }
    visible = false;
  }

  @override
  Future<Rect> bounds() async => bounds_;

  @override
  Future<void> setBounds(Rect bounds) async => bounds_ = bounds;

  @override
  Future<void> setAlwaysOnTop({required bool onTop}) async {}

  @override
  Future<void> setSkipTaskbar({required bool skip}) async {}

  @override
  Future<void> show() async => visible = true;

  @override
  Future<void> focus() async {}

  @override
  Stream<WindowFrameState> frameChanges() => _frames.stream;

  @override
  Stream<void> closeRequests() => const Stream<void>.empty();

  @override
  Future<WindowFrameState> frameState() async => const WindowFrameState(
    size: Size(360, 480),
    maximized: false,
    visible: true,
    focused: true,
  );

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<bool> isVisible() async => visible;

  @override
  Future<void> maximize() async {}

  @override
  Future<void> minimize() async {}

  @override
  Future<void> restore() async {}

  @override
  Future<void> setPreventClose({required bool prevent}) async {}

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> startDrag() async {}

  @override
  Future<void> unmaximize() async {}
}

void main() {
  group('PlacedPanelSurface dismissals', () {
    test('a toggle close should say it was the tray', () async {
      final PlacedPanelSurface panel = PlacedPanelSurface(
        window: _Window(),
        displays: const _FakeDisplays(),
      );
      addTearDown(panel.dispose);

      final Future<PanelDismissal> first = panel.dismissals().first;
      await panel.open(const PanelSpec(size: _panel));
      await panel.open(const PanelSpec(size: _panel));

      expect(
        await first.timeout(const Duration(seconds: 3)),
        PanelDismissal.trayToggled,
        reason:
            'the enum declared trayToggled and nothing ever published it, so '
            'an app syncing its tray icon never learned the panel closed',
      );
    });

    test('a direct close should say it was programmatic', () async {
      final PlacedPanelSurface panel = PlacedPanelSurface(
        window: _Window(),
        displays: const _FakeDisplays(),
      );
      addTearDown(panel.dispose);

      final Future<PanelDismissal> first = panel.dismissals().first;
      await panel.open(const PanelSpec(size: _panel));
      await panel.close();

      expect(
        await first.timeout(const Duration(seconds: 3)),
        PanelDismissal.programmatic,
      );
    });

    test('losing focus should still say it was focus', () async {
      final _Window window = _Window();
      final PlacedPanelSurface panel = PlacedPanelSurface(
        window: window,
        displays: const _FakeDisplays(),
      );
      addTearDown(panel.dispose);

      final Future<PanelDismissal> first = panel.dismissals().first;
      await panel.open(const PanelSpec(size: _panel));
      window.blur();

      expect(
        await first.timeout(const Duration(seconds: 3)),
        PanelDismissal.focusLost,
      );
    });

    test('a close that throws should reach the stream, not the void', () async {
      final _Window window = _Window(failOnHide: true);
      final PlacedPanelSurface panel = PlacedPanelSurface(
        window: window,
        displays: const _FakeDisplays(),
      );
      addTearDown(panel.dispose);

      final Future<void> failure = panel.dismissals().first;
      await panel.open(const PanelSpec(size: _panel));
      window.blur();

      await expectLater(
        failure.timeout(const Duration(seconds: 3)),
        throwsA(isA<StateError>()),
        reason:
            'the dismissal path fired and forgot the Future, so a compositor '
            'that refused to hide the window escaped the zone silently',
      );
    });
  });

  group('SocketSingleInstance lifecycle', () {
    test(
      'release then claim should still deliver a forwarded launch',
      () async {
        if (!Platform.isMacOS && !Platform.isLinux) {
          markTestSkipped('a unix domain socket is macOS and Linux only');
          return;
        }

        final Directory scratch = Directory.systemTemp.createTempSync('si');
        addTearDown(() => scratch.deleteSync(recursive: true));

        final SocketSingleInstance guard = SocketSingleInstance(
          instanceKey: 'io.example.reclaim',
          directory: scratch.path,
        );
        addTearDown(guard.dispose);

        expect(await guard.claim(), SingleInstanceVerdict.primary);
        await guard.release();
        expect(
          await guard.claim(),
          SingleInstanceVerdict.primary,
          reason: 'the socket was released, so the path is free again',
        );

        final Future<ForwardedLaunch> forwarded = guard.launches().first;

        final SocketSingleInstance second = SocketSingleInstance(
          instanceKey: 'io.example.reclaim',
          directory: scratch.path,
        );
        expect(
          await second.claim(arguments: <String>['deep://link']),
          SingleInstanceVerdict.secondary,
        );

        final ForwardedLaunch launch = await forwarded.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError(
            'nothing arrived: release() closed the launches controller and '
            'claim() could not reopen it',
          ),
        );
        expect(launch.arguments, <String>['deep://link']);
      },
    );

    test('dispose should be the terminal operation, not release', () async {
      if (!Platform.isMacOS && !Platform.isLinux) {
        markTestSkipped('a unix domain socket is macOS and Linux only');
        return;
      }

      final Directory scratch = Directory.systemTemp.createTempSync('si2');
      addTearDown(() => scratch.deleteSync(recursive: true));

      final SocketSingleInstance guard = SocketSingleInstance(
        instanceKey: 'io.example.terminal',
        directory: scratch.path,
      );
      await guard.claim();
      await guard.release();
      expect(File(guard.socketPath).existsSync(), false);

      await guard.dispose();
      await expectLater(guard.launches().toList(), completes);
    });
  });

  group('the third verdict', () {
    test('a platform without the guard should not answer primary', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        await DesktopPlatformChannel.claimSingleInstance('io.example.absent'),
        SingleInstanceVerdict.unavailable,
        reason:
            'answering primary where no guard is wired tells the caller a '
            'guarantee holds that nothing is enforcing, and on Windows that is '
            'two windows for two clicks',
      );
    });

    test('mayRun should separate running from being guarded', () {
      expect(SingleInstanceVerdict.primary.mayRun, true);
      expect(SingleInstanceVerdict.unavailable.mayRun, true);
      expect(SingleInstanceVerdict.secondary.mayRun, false);

      expect(SingleInstanceVerdict.primary.isGuarded, true);
      expect(SingleInstanceVerdict.secondary.isGuarded, true);
      expect(
        SingleInstanceVerdict.unavailable.isGuarded,
        false,
        reason: 'the one state where the app runs without a guard behind it',
      );
    });
  });

  group('the separators the two guards share', () {
    test('should be written as escapes a tool cannot eat', () {
      final String source = File(
        p.join(
          Directory.current.path,
          'lib',
          'src',
          'instance',
          'socket_single_instance.dart',
        ),
      ).readAsStringSync();

      expect(source, contains(r'\u0000'));
      expect(
        source.codeUnits.contains(0),
        false,
        reason:
            'a literal NUL byte in source is invisible to a reader, and any '
            'tool that normalises whitespace deletes it silently',
      );
    });
  });
}
