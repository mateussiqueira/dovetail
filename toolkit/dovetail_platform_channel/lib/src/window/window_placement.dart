import 'dart:convert';
import 'dart:ui';

final class WindowPlacement {
  const WindowPlacement({
    required this.size,
    required this.position,
    required this.maximized,
    this.restoredSize,
    this.restoredPosition,
  });

  const WindowPlacement.unknown()
    : size = null,
      position = null,
      maximized = false,
      restoredSize = null,
      restoredPosition = null;

  factory WindowPlacement.fromJson(Map<String, Object?> json) =>
      WindowPlacement(
        size: _size(json['width'], json['height']),
        position: _offset(json['x'], json['y']),
        maximized: json['maximized'] == true,
        restoredSize: _size(json['restoredWidth'], json['restoredHeight']),
        restoredPosition: _offset(json['restoredX'], json['restoredY']),
      );

  final Size? size;
  final Offset? position;
  final bool maximized;
  final Size? restoredSize;
  final Offset? restoredPosition;

  bool get isEmpty => size == null && position == null && !maximized;

  Map<String, Object?> toJson() => <String, Object?>{
    if (size != null) 'width': size!.width,
    if (size != null) 'height': size!.height,
    if (position != null) 'x': position!.dx,
    if (position != null) 'y': position!.dy,
    'maximized': maximized,
    if (restoredSize != null) 'restoredWidth': restoredSize!.width,
    if (restoredSize != null) 'restoredHeight': restoredSize!.height,
    if (restoredPosition != null) 'restoredX': restoredPosition!.dx,
    if (restoredPosition != null) 'restoredY': restoredPosition!.dy,
  };

  String encode() => jsonEncode(toJson());

  static WindowPlacement decode(String payload) {
    final Object? parsed = jsonDecode(payload);
    if (parsed is! Map<String, Object?>) {
      return const WindowPlacement.unknown();
    }
    return WindowPlacement.fromJson(parsed);
  }

  static Size? _size(Object? width, Object? height) {
    if (width is! num || height is! num) {
      return null;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }
    return Size(width.toDouble(), height.toDouble());
  }

  static Offset? _offset(Object? x, Object? y) {
    if (x is! num || y is! num) {
      return null;
    }
    return Offset(x.toDouble(), y.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is WindowPlacement &&
      other.size == size &&
      other.position == position &&
      other.maximized == maximized &&
      other.restoredSize == restoredSize &&
      other.restoredPosition == restoredPosition;

  @override
  int get hashCode =>
      Object.hash(size, position, maximized, restoredSize, restoredPosition);

  @override
  String toString() =>
      'WindowPlacement(size: $size, position: $position, '
      'maximized: $maximized)';
}
