import 'dart:ui';

enum PanelAnchor { trayIcon, cursor }

enum PanelSide { above, below }

enum PanelDismissal { focusLost, trayToggled, programmatic }

final class PanelSpec {
  const PanelSpec({
    required this.size,
    this.anchor = PanelAnchor.trayIcon,
    this.edgeGap = 8,
    this.dismissOnFocusLoss = true,
    this.restorePreviousPlacement = true,
  });

  final Size size;
  final PanelAnchor anchor;
  final double edgeGap;
  final bool dismissOnFocusLoss;
  final bool restorePreviousPlacement;
}

final class PanelPlacement {
  const PanelPlacement({
    required this.bounds,
    required this.side,
    required this.shrunk,
  });

  final Rect bounds;
  final PanelSide side;
  final bool shrunk;

  @override
  String toString() =>
      'PanelPlacement(bounds: $bounds, side: ${side.name}, shrunk: $shrunk)';
}
