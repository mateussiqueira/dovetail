import 'package:dovetail_shortcut_channel/src/shortcut_refusal.dart';

/// Which operating-system facility delivers system-wide shortcuts in this session.
enum ShortcutBackend {
  none(0),
  win32RegisterHotKey(1),
  carbonEventHotKey(2),
  x11GrabKey(3),
  waylandPortal(4);

  const ShortcutBackend(this.code);

  /// The value the native side reports for this backend.
  final int code;

  /// The backend for a code the native side reported; throws on a code this version does not know rather than reading it as [none].
  static ShortcutBackend fromCode(int code) => values.firstWhere(
    (ShortcutBackend backend) => backend.code == code,
    orElse: () => throw ShortcutFailure(
      ShortcutRefusal.backendUnavailable,
      'the native side reported backend $code, which this version does not '
      'know. Reading it as "none" would hide a backend that exists.',
    ),
  );

  /// Whether the application picks the chord and the system binds it with no user confirmation — true everywhere but Wayland.
  bool get grantsWithoutAsking =>
      this == ShortcutBackend.win32RegisterHotKey ||
      this == ShortcutBackend.carbonEventHotKey ||
      this == ShortcutBackend.x11GrabKey;
}
