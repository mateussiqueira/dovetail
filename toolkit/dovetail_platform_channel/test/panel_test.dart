import 'dart:async';
import 'dart:ui';

import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const Rect _macBook = Rect.fromLTWH(0, 25, 1512, 957);
const Rect _windows = Rect.fromLTWH(0, 0, 1920, 1032);
const Size _panel = Size(360, 480);

void main() {
  group('the platform resolves the panel by capability', () {
    test(
      'a linux platform should report no panel rather than an empty window',
      () async {
        const PanelSurface panel = MenuOnlyPanelSurface();
        expect(await panel.open(const PanelSpec(size: _panel)), isNull);
        expect(panel.isOpen, false);
      },
    );

    test('the panel should be reachable through the platform facade', () {
      const PanelSurface Function(DesktopPlatform) reach = _panelOf;
      expect(
        reach,
        isNotNull,
        reason:
            'this only compiles if DesktopPlatform declares panel; the '
            'capability existed and the facade had no member for it, so an app '
            'could not reach the panel through the platform it was given',
      );
      expect(
        PlatformCapability.values,
        contains(PlatformCapability.anchoredPanel),
      );
    });
  });

  group('PanelGeometry', () {
    test('a menu bar anchor should open below it', () {
      final PanelPlacement placement = PanelGeometry.place(
        anchor: const Offset(1300, 25),
        size: _panel,
        workArea: _macBook,
      );
      expect(placement.side, PanelSide.below);
      expect(placement.bounds.top, 33);
      expect(placement.shrunk, false);
    });

    test('a taskbar anchor should open above it', () {
      final PanelPlacement placement = PanelGeometry.place(
        anchor: const Offset(1800, 1032),
        size: _panel,
        workArea: _windows,
      );
      expect(placement.side, PanelSide.above);
      expect(placement.bounds.bottom, lessThanOrEqualTo(_windows.bottom - 8));
    });

    test('should centre on the anchor when there is room on both sides', () {
      expect(
        PanelGeometry.place(
          anchor: const Offset(760, 25),
          size: _panel,
          workArea: _macBook,
        ).bounds.center.dx,
        760,
      );
    });

    test('should never run off the right edge', () {
      final PanelPlacement placement = PanelGeometry.place(
        anchor: const Offset(1900, 1032),
        size: _panel,
        workArea: _windows,
      );
      expect(placement.bounds.right, _windows.right - 8);
      expect(placement.bounds.center.dx, lessThan(1900));
    });

    test('should never run off the left edge', () {
      expect(
        PanelGeometry.place(
          anchor: const Offset(4, 25),
          size: _panel,
          workArea: _macBook,
        ).bounds.left,
        _macBook.left + 8,
      );
    });

    test('should stay inside a work area that does not start at zero', () {
      const Rect second = Rect.fromLTWH(-1920, -200, 1920, 1080);
      final PanelPlacement placement = PanelGeometry.place(
        anchor: const Offset(-100, 850),
        size: _panel,
        workArea: second,
      );
      expect(second.contains(placement.bounds.topLeft), true);
      expect(
        second.contains(placement.bounds.bottomRight - const Offset(1, 1)),
        true,
      );
    });

    test('should honour the gap it was given', () {
      expect(
        PanelGeometry.place(
          anchor: const Offset(1300, 25),
          size: _panel,
          workArea: _macBook,
          gap: 24,
        ).bounds.top,
        49,
      );
    });

    test('should open on the side that has room, not the nearer half', () {
      const Rect shallow = Rect.fromLTWH(0, 0, 1920, 600);
      final PanelPlacement placement = PanelGeometry.place(
        anchor: const Offset(960, 560),
        size: _panel,
        workArea: shallow,
      );
      expect(placement.side, PanelSide.above);
      expect(placement.bounds.top, greaterThanOrEqualTo(shallow.top + 8));
      expect(placement.bounds.bottom, lessThanOrEqualTo(560 - 8));
    });

    test('a mid-screen anchor with room below should still open below', () {
      const Rect shallow = Rect.fromLTWH(0, 0, 1920, 600);
      expect(
        PanelGeometry.place(
          anchor: const Offset(960, 100),
          size: _panel,
          workArea: shallow,
        ).side,
        PanelSide.below,
      );
    });

    test('when no side has room it should still land on the screen', () {
      const Rect cramped = Rect.fromLTWH(0, 0, 1920, 560);
      final PanelPlacement placement = PanelGeometry.place(
        anchor: const Offset(960, 280),
        size: _panel,
        workArea: cramped,
      );
      expect(placement.bounds.top, greaterThanOrEqualTo(cramped.top + 8));
      expect(placement.bounds.bottom, lessThanOrEqualTo(cramped.bottom - 8));
      expect(placement.shrunk, false);
    });

    test('a panel taller than the screen should be shrunk, not clipped', () {
      const Rect tiny = Rect.fromLTWH(0, 0, 800, 300);
      final PanelPlacement placement = PanelGeometry.place(
        anchor: const Offset(400, 290),
        size: _panel,
        workArea: tiny,
      );
      expect(placement.shrunk, true);
      expect(placement.bounds.height, 300 - 16);
      expect(tiny.contains(placement.bounds.topLeft), true);
    });

    test('a panel wider than the screen should be shrunk too', () {
      const Rect narrow = Rect.fromLTWH(0, 0, 200, 900);
      final PanelPlacement placement = PanelGeometry.place(
        anchor: const Offset(100, 10),
        size: _panel,
        workArea: narrow,
      );
      expect(placement.shrunk, true);
      expect(placement.bounds.width, 200 - 16);
    });

    test('the same anchor should always land in the same place', () {
      final PanelPlacement first = PanelGeometry.place(
        anchor: const Offset(1300, 25),
        size: _panel,
        workArea: _macBook,
      );
      final PanelPlacement again = PanelGeometry.place(
        anchor: const Offset(1300, 25),
        size: _panel,
        workArea: _macBook,
      );
      expect(first.bounds, again.bounds);
    });
  });

  group('PlacedPanelSurface', () {
    late _RecordingWindow window;
    late PlacedPanelSurface panel;

    setUp(() {
      window = _RecordingWindow();
      panel = PlacedPanelSurface(
        window: window,
        displays: const _FakeDisplays(),
      );
    });

    tearDown(() => panel.dispose());

    test('should place, lift and show the window it was given', () async {
      final PanelPlacement? placement = await panel.open(
        const PanelSpec(size: _panel),
        anchorPoint: const Offset(1300, 25),
      );

      expect(placement, isNotNull);
      expect(window.bounds_, placement!.bounds);
      expect(window.alwaysOnTop, true);
      expect(window.skipTaskbar, true);
      expect(window.visible, true);
      expect(window.focused, true);
      expect(panel.isOpen, true);
    });

    test('opening it while open should close it, as a toggle does', () async {
      await panel.open(
        const PanelSpec(size: _panel),
        anchorPoint: const Offset(1300, 25),
      );
      expect(await panel.open(const PanelSpec(size: _panel)), isNull);
      expect(panel.isOpen, false);
      expect(window.visible, false);
    });

    test('closing should give the window its frame back', () async {
      window.bounds_ = const Rect.fromLTWH(300, 300, 900, 700);
      await panel.open(
        const PanelSpec(size: _panel),
        anchorPoint: const Offset(1300, 25),
      );
      await panel.close();

      expect(window.bounds_, const Rect.fromLTWH(300, 300, 900, 700));
      expect(window.alwaysOnTop, false);
      expect(window.skipTaskbar, false);
    });

    test('should not restore the frame when asked not to', () async {
      window.bounds_ = const Rect.fromLTWH(300, 300, 900, 700);
      await panel.open(
        const PanelSpec(size: _panel, restorePreviousPlacement: false),
        anchorPoint: const Offset(1300, 25),
      );
      final Rect placed = window.bounds_;
      await panel.close();
      expect(window.bounds_, placed);
    });

    test('losing focus should dismiss it and say why', () async {
      final Future<PanelDismissal> dismissal = panel.dismissals().first;
      await panel.open(
        const PanelSpec(size: _panel),
        anchorPoint: const Offset(1300, 25),
      );

      window.emitFrame(focused: false);
      expect(
        await dismissal.timeout(const Duration(seconds: 3)),
        PanelDismissal.focusLost,
      );
    });

    test('should not dismiss on focus loss when asked not to', () async {
      await panel.open(
        const PanelSpec(size: _panel, dismissOnFocusLoss: false),
        anchorPoint: const Offset(1300, 25),
      );
      window.emitFrame(focused: false);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(panel.isOpen, true);
    });

    test('a frame that keeps focus should not dismiss it', () async {
      await panel.open(
        const PanelSpec(size: _panel),
        anchorPoint: const Offset(1300, 25),
      );
      window.emitFrame(focused: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(panel.isOpen, true);
    });

    test('closing something never opened should be quiet', () async {
      await expectLater(panel.close(), completes);
      expect(window.visible, false);
    });
  });

  group('MenuOnlyPanelSurface', () {
    test('should report no panel rather than an empty window', () async {
      const MenuOnlyPanelSurface surface = MenuOnlyPanelSurface();
      expect(await surface.open(const PanelSpec(size: _panel)), isNull);
      expect(surface.isOpen, false);
      expect(await surface.dismissals().toList(), isEmpty);
    });
  });

  group('PlatformCapabilities', () {
    test(
      'an anchored panel should be absent on linux and present elsewhere',
      () {
        expect(
          const PlatformCapabilities(
            TargetPlatform.linux,
          ).supports(PlatformCapability.anchoredPanel),
          false,
        );
        for (final TargetPlatform platform in <TargetPlatform>[
          TargetPlatform.macOS,
          TargetPlatform.windows,
        ]) {
          expect(
            PlatformCapabilities(
              platform,
            ).supports(PlatformCapability.anchoredPanel),
            true,
            reason: platform.name,
          );
        }
      },
    );
  });
}

final class _FakeDisplays implements DisplayProbe {
  const _FakeDisplays();

  @override
  Future<Offset> cursorPoint() async => const Offset(1300, 25);

  @override
  Future<Rect> workAreaForPoint(Offset point) async => _macBook;

  @override
  Future<List<Rect>> workAreas() async => const <Rect>[_macBook];
}

final class _RecordingWindow implements WindowSurface {
  Rect bounds_ = Rect.zero;
  bool alwaysOnTop = false;
  bool skipTaskbar = false;
  bool visible = false;
  bool focused = false;

  final StreamController<WindowFrameState> _frames =
      StreamController<WindowFrameState>.broadcast();

  void emitFrame({required bool focused}) => _frames.add(
    WindowFrameState(
      size: bounds_.size,
      maximized: false,
      visible: visible,
      focused: focused,
    ),
  );

  @override
  Future<Rect> bounds() async => bounds_;

  @override
  Future<void> setBounds(Rect bounds) async => bounds_ = bounds;

  @override
  Future<void> setAlwaysOnTop({required bool onTop}) async =>
      alwaysOnTop = onTop;

  @override
  Future<void> setSkipTaskbar({required bool skip}) async => skipTaskbar = skip;

  @override
  Future<void> show() async {
    visible = true;
  }

  @override
  Future<void> hide() async {
    visible = false;
  }

  @override
  Future<void> focus() async {
    focused = true;
  }

  @override
  Stream<WindowFrameState> frameChanges() => _frames.stream;

  @override
  Future<WindowFrameState> frameState() async => WindowFrameState(
    size: bounds_.size,
    maximized: false,
    visible: visible,
    focused: focused,
  );

  @override
  Stream<void> closeRequests() => const Stream<void>.empty();

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

PanelSurface _panelOf(DesktopPlatform platform) => platform.panel;
