import 'package:flutter/widgets.dart';

final class ScreenshotVariant {
  const ScreenshotVariant({required this.name, required this.build});

  final String name;
  final Widget Function() build;
}
