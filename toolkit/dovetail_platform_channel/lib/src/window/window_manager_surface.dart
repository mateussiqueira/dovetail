import 'dart:async';
import 'dart:ui';

import 'package:dovetail_platform_channel/src/window/window_frame_state.dart';
import 'package:dovetail_platform_channel/src/window/window_spec.dart';
import 'package:dovetail_platform_channel/src/window/window_surface.dart';
import 'package:window_manager/window_manager.dart';

final class WindowManagerSurface with WindowListener implements WindowSurface {
  WindowManagerSurface({WindowManager? manager})
    : _manager = manager ?? windowManager;

  final WindowManager _manager;

  final StreamController<void> _closeRequests =
      StreamController<void>.broadcast();
  final StreamController<WindowFrameState> _frameChanges =
      StreamController<WindowFrameState>.broadcast();

  bool _attached = false;

  Future<void> attach(WindowSpec spec) async {
    if (_attached) {
      return;
    }
    await _manager.ensureInitialized();

    final WindowOptions options = WindowOptions(
      size: spec.size,
      minimumSize: spec.minimumSize,
      center: spec.centered,
      title: spec.title,
      skipTaskbar: spec.skipTaskbar,
      titleBarStyle: spec.frameless
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
    );

    _manager.addListener(this);
    _attached = true;

    await _manager.waitUntilReadyToShow(options, () async {
      if (spec.visibleOnStart) {
        await _manager.show();
        await _manager.focus();
      }
    });
  }

  Future<void> detach() async {
    if (!_attached) {
      return;
    }
    _manager.removeListener(this);
    _attached = false;
  }

  Future<void> dispose() async {
    await detach();
    await _closeRequests.close();
    await _frameChanges.close();
  }

  @override
  Future<void> show() => _manager.show();

  @override
  Future<void> hide() => _manager.hide();

  @override
  Future<void> focus() => _manager.focus();

  @override
  Future<void> minimize() => _manager.minimize();

  @override
  Future<void> restore() => _manager.restore();

  @override
  Future<void> maximize() => _manager.maximize();

  @override
  Future<void> unmaximize() => _manager.unmaximize();

  @override
  Future<bool> isMaximized() => _manager.isMaximized();

  @override
  Future<bool> isVisible() => _manager.isVisible();

  @override
  Future<void> startDrag() => _manager.startDragging();

  @override
  Future<void> setTitle(String title) => _manager.setTitle(title);

  @override
  Future<void> setPreventClose({required bool prevent}) =>
      _manager.setPreventClose(prevent);

  @override
  Future<void> setSkipTaskbar({required bool skip}) =>
      _manager.setSkipTaskbar(skip);

  @override
  Future<void> setAlwaysOnTop({required bool onTop}) =>
      _manager.setAlwaysOnTop(onTop);

  @override
  Future<void> setBounds(Rect bounds) => _manager.setBounds(bounds);

  @override
  Future<Rect> bounds() => _manager.getBounds();

  @override
  Future<WindowFrameState> frameState() async {
    final Size size = await _manager.getSize();
    final bool maximized = await _manager.isMaximized();
    final bool visible = await _manager.isVisible();
    final bool focused = await _manager.isFocused();

    return WindowFrameState(
      size: size,
      maximized: maximized,
      visible: visible,
      focused: focused,
    );
  }

  @override
  Stream<WindowFrameState> frameChanges() => _frameChanges.stream;

  @override
  Stream<void> closeRequests() => _closeRequests.stream;

  @override
  void onWindowClose() {
    if (!_closeRequests.isClosed) {
      _closeRequests.add(null);
    }
  }

  @override
  void onWindowResized() => _publishFrame();

  @override
  void onWindowMaximize() => _publishFrame();

  @override
  void onWindowUnmaximize() => _publishFrame();

  @override
  void onWindowFocus() => _publishFrame();

  @override
  void onWindowBlur() => _publishFrame();

  Future<void> _publishFrame() async {
    if (_frameChanges.isClosed) {
      return;
    }
    _frameChanges.add(await frameState());
  }
}
