/// Why a field did not pass.
///
/// The rule that broke, not the sentence to show. A validator that returned
/// text would have to be rebuilt every time the language changes, and one
/// that returned a translation key would need a lookup by string that the
/// generated `AppL10n` deliberately does not have. A sealed type is the
/// third option: the caller switches over it, the switch is exhaustive, and
/// adding a rule here breaks that switch at compile time rather than in
/// front of a user.
///
/// Several of these carry the numbers that produced them, so that a message
/// can be specific — "faltam 3 caracteres" rather than "muito curto".
sealed class ValidationFailure {
  const ValidationFailure(this.field);

  /// The key in the input map that failed.
  final String field;
}

/// The field was empty, or only whitespace.
final class FieldIsRequired extends ValidationFailure {
  const FieldIsRequired(super.field);

  @override
  String toString() => 'FieldIsRequired($field)';
}

/// The field has fewer characters than [minimum]; [actual] says how many it has.
final class FieldIsTooShort extends ValidationFailure {
  const FieldIsTooShort(
    super.field, {
    required this.minimum,
    required this.actual,
  });

  /// The smallest length the rule accepts.
  final int minimum;

  /// The length the value had.
  final int actual;

  @override
  String toString() => 'FieldIsTooShort($field, $actual < $minimum)';
}

/// The field does not read as an e-mail address.
final class FieldIsNotAnEmail extends ValidationFailure {
  const FieldIsNotAnEmail(super.field);

  @override
  String toString() => 'FieldIsNotAnEmail($field)';
}

/// The field has the right length but something in it is not a digit.
final class FieldIsNotDigits extends ValidationFailure {
  const FieldIsNotDigits(super.field);

  @override
  String toString() => 'FieldIsNotDigits($field)';
}

/// The field has [actual] characters where exactly [expected] were required.
final class FieldHasWrongLength extends ValidationFailure {
  const FieldHasWrongLength(
    super.field, {
    required this.expected,
    required this.actual,
  });

  /// The one length the rule accepts.
  final int expected;

  /// The length the value had.
  final int actual;

  @override
  String toString() => 'FieldHasWrongLength($field, $actual != $expected)';
}

/// The field differs from the field named [other] — a password and its confirmation, typically.
final class FieldsDoNotMatch extends ValidationFailure {
  const FieldsDoNotMatch(super.field, {required this.other});

  /// The key of the field this one had to equal.
  final String other;

  @override
  String toString() => 'FieldsDoNotMatch($field, $other)';
}

/// The field is not a real calendar date in `YYYY-MM-DD` form. The thirtieth of February lands here.
final class FieldIsNotADate extends ValidationFailure {
  const FieldIsNotADate(super.field);

  @override
  String toString() => 'FieldIsNotADate($field)';
}

/// The date is before [earliestYear].
final class FieldIsTooOld extends ValidationFailure {
  const FieldIsTooOld(super.field, {required this.earliestYear});

  /// The first year the rule accepts.
  final int earliestYear;

  @override
  String toString() => 'FieldIsTooOld($field, before $earliestYear)';
}

/// The date is after today.
final class FieldIsInTheFuture extends ValidationFailure {
  const FieldIsInTheFuture(super.field);

  @override
  String toString() => 'FieldIsInTheFuture($field)';
}
