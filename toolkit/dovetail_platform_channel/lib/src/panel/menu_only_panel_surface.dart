import 'dart:ui';

import 'package:dovetail_platform_channel/src/panel/panel_spec.dart';
import 'package:dovetail_platform_channel/src/panel/panel_surface.dart';

final class MenuOnlyPanelSurface implements PanelSurface {
  const MenuOnlyPanelSurface();

  @override
  bool get isOpen => false;

  @override
  Stream<PanelDismissal> dismissals() => const Stream<PanelDismissal>.empty();

  @override
  Future<PanelPlacement?> open(PanelSpec spec, {Offset? anchorPoint}) async =>
      null;

  @override
  Future<void> close([
    PanelDismissal reason = PanelDismissal.programmatic,
  ]) async {}

  @override
  Future<void> dispose() async {}
}
