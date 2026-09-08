import 'package:dovetail_shortcut_channel/src/shortcut_chord.dart';
import 'package:dovetail_shortcut_channel/src/shortcut_refusal.dart';

/// The operating system the policy and the probe reason about.
enum ShortcutHost { windows, macos, linux, other }

/// The chords this channel refuses before asking the system, because the system would accept them and they would still be wrong.
///
/// A chord with no primary modifier, F12, Windows-key chords on Windows, Option-only chords on macOS: each one binds and then fails in a way the call site never sees.
final class ShortcutPolicy {
  /// The default policy.
  const ShortcutPolicy();

  /// Keys refused on every platform, because they are reserved on at least one.
  static const Set<String> reservedEverywhere = <String>{'F12'};

  /// The reason [chord] is refused on [host], or `null` when it may be bound.
  String? refuse(ShortcutChord chord, ShortcutHost host) {
    if (!chord.carriesPrimaryModifier) {
      return 'a chord without Control, Command or Meta is one keystroke away '
          'from every other application on the machine';
    }
    if (reservedEverywhere.contains(chord.code)) {
      return '${chord.code} is reserved for the debugger on Windows, and a '
          'chord that works on two platforms out of three is a support call';
    }
    if (host == ShortcutHost.windows &&
        chord.modifiers.contains(ShortcutModifier.meta)) {
      return 'Windows reserves the combinations that carry its own key; '
          'RegisterHotKey refuses them';
    }
    if (host == ShortcutHost.macos && _optionOnly(chord)) {
      return 'macOS 15.0 stopped delivering Option-only and Option+Shift '
          'chords to sandboxed applications, and it did so without an error '
          'at the call site';
    }
    return null;
  }

  /// Throws [ShortcutFailure] with [ShortcutRefusal.refusedByPolicy] when [refuse] has a reason.
  void enforce(ShortcutChord chord, ShortcutHost host) {
    final String? reason = refuse(chord, host);
    if (reason != null) {
      throw ShortcutFailure(ShortcutRefusal.refusedByPolicy, reason);
    }
  }

  bool _optionOnly(ShortcutChord chord) =>
      chord.modifiers.contains(ShortcutModifier.alt) &&
      !chord.modifiers.contains(ShortcutModifier.control) &&
      !chord.modifiers.contains(ShortcutModifier.meta) &&
      !chord.modifiers.contains(ShortcutModifier.commandOrControl);
}
