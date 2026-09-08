import 'dart:ui';

abstract interface class DisplayProbe {
  Future<Offset> cursorPoint();
  Future<Rect> workAreaForPoint(Offset point);
  Future<List<Rect>> workAreas();
}
