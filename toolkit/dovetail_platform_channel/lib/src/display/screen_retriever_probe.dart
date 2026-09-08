import 'dart:ui';

import 'package:dovetail_platform_channel/src/display/display_probe.dart';
import 'package:screen_retriever/screen_retriever.dart';

final class ScreenRetrieverProbe implements DisplayProbe {
  ScreenRetrieverProbe({ScreenRetriever? retriever})
    : _retriever = retriever ?? screenRetriever;

  final ScreenRetriever _retriever;

  @override
  Future<Offset> cursorPoint() => _retriever.getCursorScreenPoint();

  @override
  Future<List<Rect>> workAreas() async {
    final List<Display> displays = await _retriever.getAllDisplays();
    return displays.map(workAreaOf).toList(growable: false);
  }

  @override
  Future<Rect> workAreaForPoint(Offset point) async {
    final List<Display> displays = await _retriever.getAllDisplays();
    for (final Display display in displays) {
      final Rect area = workAreaOf(display);
      if (area.contains(point)) {
        return area;
      }
    }
    return workAreaOf(await _retriever.getPrimaryDisplay());
  }

  static Rect workAreaOf(Display display) {
    final Offset origin = display.visiblePosition ?? Offset.zero;
    final Size size = display.visibleSize ?? display.size;
    return Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
  }
}
