import 'dart:ui';

import 'package:dovetail_platform_channel/src/window/window_frame_state.dart';

abstract interface class WindowSurface {
  Future<void> show();
  Future<void> hide();
  Future<void> focus();
  Future<void> minimize();
  Future<void> restore();
  Future<void> maximize();
  Future<void> unmaximize();
  Future<bool> isMaximized();
  Future<bool> isVisible();
  Future<WindowFrameState> frameState();
  Future<void> startDrag();
  Future<void> setTitle(String title);
  Future<void> setPreventClose({required bool prevent});
  Future<void> setSkipTaskbar({required bool skip});
  Future<void> setAlwaysOnTop({required bool onTop});
  Future<void> setBounds(Rect bounds);
  Future<Rect> bounds();

  Stream<WindowFrameState> frameChanges();
  Stream<void> closeRequests();
}
