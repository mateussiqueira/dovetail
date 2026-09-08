import 'package:dovetail_shortcut_channel/src/session_probe.dart';
import 'package:dovetail_shortcut_channel/src/shortcut_chord.dart';
import 'package:dovetail_shortcut_channel/src/shortcut_refusal.dart';

final class ShortcutRequest {
  const ShortcutRequest({required this.name, required this.chord});

  final String name;
  final ShortcutChord chord;
}

sealed class ShortcutOutcome {
  const ShortcutOutcome(this.name);

  final String name;
}

final class ShortcutBound extends ShortcutOutcome {
  const ShortcutBound(super.name, this.chord, this.nativeId);

  final ShortcutChord chord;
  final int nativeId;
}

final class ShortcutRefused extends ShortcutOutcome {
  const ShortcutRefused(super.name, this.reason, this.detail);

  final ShortcutRefusal reason;
  final String detail;
}

final class ShortcutPress {
  const ShortcutPress({required this.name, required this.pressed});

  final String name;
  final bool pressed;
}

abstract interface class GlobalShortcutSurface {
  ShortcutSupport get support;

  Stream<ShortcutPress> presses();

  Future<List<ShortcutOutcome>> bind(List<ShortcutRequest> requests);

  Future<void> release(String name);

  Future<void> releaseAll();

  Future<void> dispose();
}
