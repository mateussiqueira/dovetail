import 'package:dovetail_shortcut_channel/src/shortcut_refusal.dart';

/// A modifier key in a chord, named the way accelerators spell it.
enum ShortcutModifier {
  commandOrControl('CommandOrControl'),
  control('Control'),
  meta('Meta'),
  alt('Alt'),
  shift('Shift');

  const ShortcutModifier(this.acceleratorName);

  /// How this modifier is spelled in an accelerator string such as `CommandOrControl+Shift+K`.
  final String acceleratorName;
}

/// A key plus its modifiers — what a shortcut is bound to.
///
/// Built directly or parsed from an accelerator string; refuses a chord with no key or with modifiers hidden inside the key name.
final class ShortcutChord {
  /// A chord on [code] with [modifiers]. Throws [ShortcutFailure] with [ShortcutRefusal.malformedChord] when the key is empty or carries a `+`.
  ShortcutChord({
    required this.code,
    Set<ShortcutModifier> modifiers = const <ShortcutModifier>{},
  }) : modifiers = Set<ShortcutModifier>.unmodifiable(modifiers) {
    if (code.trim().isEmpty) {
      throw const ShortcutFailure(
        ShortcutRefusal.malformedChord,
        'a chord with no key is not a chord',
      );
    }
    if (code.contains('+') || code.trim() != code) {
      throw ShortcutFailure(
        ShortcutRefusal.malformedChord,
        'the key is "$code"; a chord carries its modifiers in the set, not '
        'inside the key name',
      );
    }
  }

  /// Parses `Modifier+Modifier+Key`; modifier names are case-insensitive and accept the usual aliases (`Ctrl`, `Cmd`, `Option`, `Super`).
  factory ShortcutChord.parse(String accelerator) {
    final List<String> parts = accelerator
        .split('+')
        .map((String part) => part.trim())
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      throw const ShortcutFailure(
        ShortcutRefusal.malformedChord,
        'the accelerator is empty',
      );
    }

    final Set<ShortcutModifier> modifiers = <ShortcutModifier>{};
    for (final String part in parts.sublist(0, parts.length - 1)) {
      modifiers.add(_modifierNamed(part));
    }
    return ShortcutChord(code: parts.last, modifiers: modifiers);
  }

  /// The key, as the accelerator names it — `K`, `F5`, `Space`.
  final String code;

  /// The modifiers held with the key; unmodifiable.
  final Set<ShortcutModifier> modifiers;

  /// The chord as an accelerator string, modifiers in canonical order.
  String get accelerator => <String>[
    for (final ShortcutModifier modifier in ShortcutModifier.values)
      if (modifiers.contains(modifier)) modifier.acceleratorName,
    code,
  ].join('+');

  /// Whether Control, Meta or CommandOrControl is held — the difference between a shortcut and a keystroke every other app also receives.
  bool get carriesPrimaryModifier =>
      modifiers.contains(ShortcutModifier.control) ||
      modifiers.contains(ShortcutModifier.meta) ||
      modifiers.contains(ShortcutModifier.commandOrControl);

  @override
  bool operator ==(Object other) =>
      other is ShortcutChord &&
      other.code == code &&
      other.modifiers.length == modifiers.length &&
      other.modifiers.containsAll(modifiers);

  @override
  int get hashCode => Object.hash(code, Object.hashAllUnordered(modifiers));

  @override
  String toString() => accelerator;

  static ShortcutModifier _modifierNamed(String name) {
    final String normalized = name.toLowerCase();
    return switch (normalized) {
      'control' || 'ctrl' => ShortcutModifier.control,
      'alt' || 'option' => ShortcutModifier.alt,
      'shift' => ShortcutModifier.shift,
      'meta' || 'super' || 'command' || 'cmd' || 'win' => ShortcutModifier.meta,
      'commandorcontrol' || 'cmdorctrl' => ShortcutModifier.commandOrControl,
      _ => throw ShortcutFailure(
        ShortcutRefusal.malformedChord,
        '"$name" is not a modifier this channel knows',
      ),
    };
  }
}
