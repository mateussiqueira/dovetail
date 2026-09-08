import 'dart:ui';

final class WindowFrameState {
  const WindowFrameState({
    required this.size,
    required this.maximized,
    required this.visible,
    required this.focused,
  });

  final Size size;
  final bool maximized;
  final bool visible;
  final bool focused;

  @override
  bool operator ==(Object other) =>
      other is WindowFrameState &&
      other.size == size &&
      other.maximized == maximized &&
      other.visible == visible &&
      other.focused == focused;

  @override
  int get hashCode => Object.hash(size, maximized, visible, focused);

  @override
  String toString() =>
      'WindowFrameState(size: $size, maximized: $maximized, '
      'visible: $visible, focused: $focused)';
}
