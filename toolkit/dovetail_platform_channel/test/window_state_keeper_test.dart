import 'dart:async';
import 'dart:ui';

import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';

const Rect _screen = Rect.fromLTWH(0, 25, 1512, 957);
const Rect _saved = Rect.fromLTWH(200, 120, 1000, 700);

final class _Displays implements DisplayProbe {
  const _Displays([this.areas = const <Rect>[_screen]]);

  final List<Rect> areas;

  @override
  Future<Offset> cursorPoint() async => Offset.zero;

  @override
  Future<Rect> workAreaForPoint(Offset point) async => areas.first;

  @override
  Future<List<Rect>> workAreas() async => areas;
}

final class _MemoryStore implements WindowStateStore {
  _MemoryStore([this._held = const WindowPlacement.unknown()]);

  WindowPlacement _held;
  int saves = 0;

  @override
  WindowPlacement load() => _held;

  @override
  void save(WindowPlacement placement) {
    _held = placement;
    saves++;
  }

  @override
  void clear() => _held = const WindowPlacement.unknown();

  WindowPlacement get held => _held;
}

final class _Window implements WindowSurface {
  Rect bounds_ = const Rect.fromLTWH(0, 0, 800, 600);
  bool maximized = false;
  final StreamController<WindowFrameState> frames =
      StreamController<WindowFrameState>.broadcast();

  void emitFrame() => frames.add(
    WindowFrameState(
      size: bounds_.size,
      maximized: maximized,
      visible: true,
      focused: true,
    ),
  );

  @override
  Future<Rect> bounds() async => bounds_;

  @override
  Future<void> setBounds(Rect bounds) async => bounds_ = bounds;

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> maximize() async => maximized = true;

  @override
  Stream<WindowFrameState> frameChanges() => frames.stream;

  @override
  Future<void> hide() async {}
  @override
  Future<void> show() async {}
  @override
  Future<void> focus() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> restore() async {}
  @override
  Future<void> unmaximize() async => maximized = false;
  @override
  Future<bool> isVisible() async => true;
  @override
  Future<void> startDrag() async {}
  @override
  Future<void> setTitle(String title) async {}
  @override
  Future<void> setPreventClose({required bool prevent}) async {}
  @override
  Future<void> setSkipTaskbar({required bool skip}) async {}
  @override
  Future<void> setAlwaysOnTop({required bool onTop}) async {}
  @override
  Future<WindowFrameState> frameState() async => WindowFrameState(
    size: bounds_.size,
    maximized: maximized,
    visible: true,
    focused: true,
  );
  @override
  Stream<void> closeRequests() => const Stream<void>.empty();
}

void main() {
  late _Window window;

  setUp(() => window = _Window());

  WindowStateKeeper keeperOver(
    _MemoryStore store, {
    List<Rect> screens = const <Rect>[_screen],
    Duration settle = const Duration(milliseconds: 30),
  }) => WindowStateKeeper(
    window: window,
    store: store,
    displays: _Displays(screens),
    settleFor: settle,
  );

  group('restoring', () {
    test('a saved frame should be applied', () async {
      final _MemoryStore store = _MemoryStore(
        const WindowPlacement(
          size: Size(1000, 700),
          position: Offset(200, 120),
          maximized: false,
        ),
      );

      await keeperOver(store).restore();

      expect(window.bounds_, _saved);
    });

    test('nothing saved should leave the window where it is', () async {
      final Rect before = window.bounds_;

      await keeperOver(_MemoryStore()).restore();

      expect(window.bounds_, before);
    });

    test('a frame off every screen should not be applied', () async {
      final _MemoryStore store = _MemoryStore(
        const WindowPlacement(
          size: Size(800, 600),
          position: Offset(-9000, -9000),
          maximized: false,
        ),
      );
      final Rect before = window.bounds_;

      await keeperOver(store).restore();

      expect(
        window.bounds_,
        before,
        reason:
            'a monitor unplugged between sessions leaves a saved position on '
            'no screen, and a window opened there is a window the user cannot '
            'find',
      );
    });

    test('a maximized window should come back maximized', () async {
      final _MemoryStore store = _MemoryStore(
        const WindowPlacement(
          size: Size(1512, 957),
          position: Offset(0, 25),
          maximized: true,
          restoredSize: Size(1000, 700),
          restoredPosition: Offset(200, 120),
        ),
      );

      await keeperOver(store).restore();

      expect(window.maximized, true);
    });
  });

  group('saving', () {
    test('the current frame should be written', () async {
      final _MemoryStore store = _MemoryStore();
      window.bounds_ = _saved;

      await keeperOver(store).save();

      expect(store.held.size, _saved.size);
      expect(store.held.position, _saved.topLeft);
      expect(store.held.maximized, false);
    });

    test('a maximized window should keep the frame to restore to', () async {
      final _MemoryStore store = _MemoryStore();
      final WindowStateKeeper keeper = keeperOver(store);

      window.bounds_ = _saved;
      await keeper.save();

      window
        ..maximized = true
        ..bounds_ = _screen;
      await keeper.save();

      expect(store.held.maximized, true);
      expect(
        store.held.restoredSize,
        _saved.size,
        reason:
            'restoring a window that only ever saved its maximized frame '
            'un-maximizes it to the size of the screen',
      );
      expect(store.held.restoredPosition, _saved.topLeft);
    });

    test('a burst of frame events should settle into one save', () async {
      final _MemoryStore store = _MemoryStore();
      final WindowStateKeeper keeper = keeperOver(store)..watch();
      addTearDown(keeper.dispose);

      for (int i = 0; i < 12; i++) {
        window
          ..bounds_ = Rect.fromLTWH(100 + i.toDouble(), 100, 900, 600)
          ..emitFrame();
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        store.saves,
        1,
        reason:
            'a drag emits a frame event per pixel, and writing the file on '
            'each one turns a window move into hundreds of disk writes',
      );
      expect(store.held.position, const Offset(111, 100));
    });

    test('nothing should be saved after dispose', () async {
      final _MemoryStore store = _MemoryStore();
      final WindowStateKeeper keeper = keeperOver(store)..watch();

      window.emitFrame();
      await keeper.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(store.saves, 0);
    });

    test('watch twice should not subscribe twice', () async {
      final _MemoryStore store = _MemoryStore();
      final WindowStateKeeper keeper = keeperOver(store)
        ..watch()
        ..watch();
      addTearDown(keeper.dispose);

      window.emitFrame();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(store.saves, 1);
    });
  });

  group('a round trip', () {
    test('what one session saved should be what the next restores', () async {
      final _MemoryStore store = _MemoryStore();

      window.bounds_ = _saved;
      await keeperOver(store).save();

      final _Window next = _Window();
      window = next;
      await keeperOver(store).restore();

      expect(next.bounds_, _saved);
    });
  });
}
