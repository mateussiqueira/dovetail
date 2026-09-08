/// Why a shortcut could not be bound, released or delivered.
enum ShortcutRefusal {
  platformUnsupported(-1),
  malformedChord(1),
  takenBySystem(2),
  alreadyBound(3),
  notBound(4),
  backendUnavailable(5),
  sessionUnsupported(-2),
  refusedByPolicy(-5);

  const ShortcutRefusal(this.code);

  /// The status value the native side uses for this refusal; negative ones are decided on the Dart side.
  final int code;

  /// The refusal for a native status; throws on one this version does not know rather than reporting the wrong cause.
  static ShortcutRefusal fromStatus(int status) => values.firstWhere(
    (ShortcutRefusal refusal) => refusal.code == status,
    orElse: () => throw ShortcutFailure(
      ShortcutRefusal.backendUnavailable,
      'the native side reported status $status, which this version does not '
      'know. Folding it into backendUnavailable would report the wrong cause.',
    ),
  );
}

/// A refusal with the sentence that explains it.
final class ShortcutFailure implements Exception {
  /// A failure for [reason], explained by [detail].
  const ShortcutFailure(this.reason, this.detail);

  /// What went wrong, as a value a caller can switch on.
  final ShortcutRefusal reason;

  /// The explanation, written for the person reading the log.
  final String detail;

  @override
  String toString() => '${reason.name}: $detail';
}
