import 'dart:async';
import 'dart:ui';

import 'package:dovetail_platform_channel/src/display/display_probe.dart';
import 'package:dovetail_platform_channel/src/window/placement_guard.dart';
import 'package:dovetail_platform_channel/src/window/window_frame_state.dart';
import 'package:dovetail_platform_channel/src/window/window_placement.dart';
import 'package:dovetail_platform_channel/src/window/window_state_store.dart';
import 'package:dovetail_platform_channel/src/window/window_surface.dart';

final class WindowStateKeeper {
  WindowStateKeeper({
    required this.window,
    required this.store,
    required this.displays,
    this.settleFor = const Duration(milliseconds: 400),
  });

  final WindowSurface window;
  final WindowStateStore store;
  final DisplayProbe displays;
  final Duration settleFor;

  StreamSubscription<WindowFrameState>? _watching;
  Timer? _settling;
  Rect? _lastRestoredFrame;

  Future<WindowPlacement> restore() async {
    final WindowPlacement saved = store.load();
    final WindowPlacement placement = PlacementGuard.clampToScreens(
      saved,
      await displays.workAreas(),
    );

    final Size? size = placement.size;
    final Offset? position = placement.position;
    if (size != null && position != null) {
      await window.setBounds(
        Rect.fromLTWH(position.dx, position.dy, size.width, size.height),
      );
    }
    if (placement.maximized) {
      await window.maximize();
    }

    _lastRestoredFrame = _frameOf(
      placement.restoredSize,
      placement.restoredPosition,
    );
    return placement;
  }

  void watch() {
    _watching ??= window.frameChanges().listen((WindowFrameState _) {
      _settling?.cancel();
      _settling = Timer(settleFor, () => unawaited(save()));
    });
  }

  Future<void> save() async {
    final bool maximized = await window.isMaximized();
    final Rect bounds = await window.bounds();

    if (!maximized) {
      _lastRestoredFrame = bounds;
    }
    final Rect? restored = _lastRestoredFrame;

    store.save(
      WindowPlacement(
        size: bounds.size,
        position: bounds.topLeft,
        maximized: maximized,
        restoredSize: restored?.size,
        restoredPosition: restored?.topLeft,
      ),
    );
  }

  Future<void> dispose() async {
    _settling?.cancel();
    _settling = null;
    await _watching?.cancel();
    _watching = null;
  }

  static Rect? _frameOf(Size? size, Offset? position) {
    if (size == null || position == null) {
      return null;
    }
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }
}
