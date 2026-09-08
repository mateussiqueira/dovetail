import 'dart:ui';

final class WindowSpec {
  const WindowSpec({
    required this.size,
    required this.minimumSize,
    this.title = '',
    this.centered = true,
    this.frameless = true,
    this.visibleOnStart = true,
    this.skipTaskbar = false,
  });

  final Size size;
  final Size minimumSize;
  final String title;
  final bool centered;
  final bool frameless;
  final bool visibleOnStart;
  final bool skipTaskbar;
}
