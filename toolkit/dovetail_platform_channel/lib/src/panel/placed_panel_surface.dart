import 'dart:async';
import 'dart:ui';

import 'package:dovetail_platform_channel/src/display/display_probe.dart';
import 'package:dovetail_platform_channel/src/panel/panel_spec.dart';
import 'package:dovetail_platform_channel/src/panel/panel_geometry.dart';
import 'package:dovetail_platform_channel/src/panel/panel_surface.dart';
import 'package:dovetail_platform_channel/src/window/window_frame_state.dart';
import 'package:dovetail_platform_channel/src/window/window_surface.dart';

final class PlacedPanelSurface implements PanelSurface {
  PlacedPanelSurface({required this.window, required this.displays});

  final WindowSurface window;
  final DisplayProbe displays;
  final StreamController<PanelDismissal> _dismissals =
      StreamController<PanelDismissal>.broadcast();

  StreamSubscription<WindowFrameState>? _frames;
  Rect? _restore;
  PanelSpec? _open;

  @override
  bool get isOpen => _open != null;

  @override
  Stream<PanelDismissal> dismissals() => _dismissals.stream;

  @override
  Future<PanelPlacement?> open(PanelSpec spec, {Offset? anchorPoint}) async {
    if (_open != null) {
      await close(PanelDismissal.trayToggled);
      return null;
    }

    final Offset anchor = anchorPoint ?? await displays.cursorPoint();
    final Rect workArea = await displays.workAreaForPoint(anchor);
    final PanelPlacement placement = PanelGeometry.place(
      anchor: anchor,
      size: spec.size,
      workArea: workArea,
      gap: spec.edgeGap,
    );

    if (spec.restorePreviousPlacement) {
      _restore = await window.bounds();
    }

    _open = spec;
    await window.setSkipTaskbar(skip: true);
    await window.setAlwaysOnTop(onTop: true);
    await window.setBounds(placement.bounds);
    await window.show();
    await window.focus();

    if (spec.dismissOnFocusLoss) {
      _frames = window.frameChanges().listen(_onFrame);
    }

    return placement;
  }

  @override
  @override
  Future<void> close([
    PanelDismissal reason = PanelDismissal.programmatic,
  ]) async {
    if (_open == null) {
      return;
    }
    final PanelSpec spec = _open!;
    _open = null;

    await _frames?.cancel();
    _frames = null;

    await window.hide();
    await window.setAlwaysOnTop(onTop: false);
    await window.setSkipTaskbar(skip: false);

    final Rect? restore = _restore;
    _restore = null;
    if (spec.restorePreviousPlacement && restore != null) {
      await window.setBounds(restore);
    }

    _publish(reason);
  }

  @override
  Future<void> dispose() async {
    await _frames?.cancel();
    _frames = null;
    _open = null;
    await _dismissals.close();
  }

  void _onFrame(WindowFrameState state) {
    if (_open == null || state.focused) {
      return;
    }
    close(PanelDismissal.focusLost).catchError((
      Object error,
      StackTrace trace,
    ) {
      if (!_dismissals.isClosed) {
        _dismissals.addError(error, trace);
      }
    });
  }

  void _publish(PanelDismissal dismissal) {
    if (!_dismissals.isClosed) {
      _dismissals.add(dismissal);
    }
  }
}
