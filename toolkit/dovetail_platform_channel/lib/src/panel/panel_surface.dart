import 'dart:ui';

import 'package:dovetail_platform_channel/src/panel/panel_spec.dart';

abstract interface class PanelSurface {
  Future<PanelPlacement?> open(PanelSpec spec, {Offset? anchorPoint});
  Future<void> close([PanelDismissal reason]);
  bool get isOpen;
  Stream<PanelDismissal> dismissals();
  Future<void> dispose();
}
