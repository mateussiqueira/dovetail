import 'failure.dart';

/// One rule against one field.
///
/// The input is a map of what the form holds. Absent and null read as empty:
/// a form field that was never touched and one that was cleared are the same
/// thing to every rule here, and making the caller normalise that is how a
/// null slips through as "valid".
abstract interface class FieldValidation {
  /// The key in the input map this rule reads.
  String get field;

  /// The failure for [input], or `null` when the field passes.
  ValidationFailure? validate(Map<String, String?> input);
}

String _valueOf(Map<String, String?> input, String field) => input[field] ?? '';

/// The field must have something in it besides whitespace.
final class RequiredField implements FieldValidation {
  /// Requires [field].
  const RequiredField(this.field);

  @override
  final String field;

  @override
  ValidationFailure? validate(Map<String, String?> input) =>
      _valueOf(input, field).trim().isEmpty ? FieldIsRequired(field) : null;
}

/// The field must have at least [minimum] characters.
final class MinLength implements FieldValidation {
  /// Requires [minimum] characters in [field]; see [trimmed] for whether the edges count.
  const MinLength(this.field, this.minimum, {this.trimmed = false});

  @override
  final String field;

  /// The smallest length accepted.
  final int minimum;

  /// Whether the surrounding whitespace counts. A password's does; a name's
  /// does not, and the old front end had two separate rules for the
  /// distinction rather than a flag.
  final bool trimmed;

  @override
  ValidationFailure? validate(Map<String, String?> input) {
    final String value = _valueOf(input, field);
    final int length = (trimmed ? value.trim() : value).length;
    return length >= minimum
        ? null
        : FieldIsTooShort(field, minimum: minimum, actual: length);
  }
}

/// The field must read as an e-mail address, by the same expression the previous front end used.
final class Email implements FieldValidation {
  /// Requires an address in [field].
  const Email(this.field);

  /// Carried over character for character from the front end this replaces.
  /// Not because it is the best expression of an address — no regexp is —
  /// but because changing it would start rejecting accounts that signed up
  /// through the old app, and that is a product decision, not a port.
  static final RegExp _format = RegExp(
    r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)*\.[^\s@.]{2,}$',
  );

  @override
  final String field;

  @override
  ValidationFailure? validate(Map<String, String?> input) =>
      _format.hasMatch(_valueOf(input, field).trim())
      ? null
      : FieldIsNotAnEmail(field);
}

/// The field must be exactly [length] digits — a PIN, a confirmation code.
final class Digits implements FieldValidation {
  /// Requires [length] digits in [field].
  const Digits(this.field, this.length);

  static final RegExp _onlyDigits = RegExp(r'^\d+$');

  @override
  final String field;

  /// The exact number of digits.
  final int length;

  @override
  ValidationFailure? validate(Map<String, String?> input) {
    final String value = _valueOf(input, field);
    // Length first, then shape: a six-digit PIN typed as five digits is a
    // different mistake from one typed with a letter in it, and the person
    // typing deserves to be told which.
    if (value.length != length) {
      return FieldHasWrongLength(field, expected: length, actual: value.length);
    }
    return _onlyDigits.hasMatch(value) ? null : FieldIsNotDigits(field);
  }
}

/// The field must equal the field named [other].
final class SameAs implements FieldValidation {
  /// Requires [field] to equal [other].
  const SameAs(this.field, this.other);

  @override
  final String field;

  /// The key of the field to compare against.
  final String other;

  @override
  ValidationFailure? validate(Map<String, String?> input) =>
      _valueOf(input, field) == _valueOf(input, other)
      ? null
      : FieldsDoNotMatch(field, other: other);
}

/// The field must be a real `YYYY-MM-DD` date, not before [earliestYear] and not after today.
final class PastDate implements FieldValidation {
  /// Requires a past date in [field], no earlier than [earliestYear].
  const PastDate(this.field, this.earliestYear, {this.now = DateTime.now});

  static final RegExp _iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  @override
  final String field;

  /// The first year accepted.
  final int earliestYear;

  /// Injected so a test can say what day it is instead of hoping.
  final DateTime Function() now;

  @override
  ValidationFailure? validate(Map<String, String?> input) {
    final String value = _valueOf(input, field);
    if (!_iso.hasMatch(value)) {
      return FieldIsNotADate(field);
    }

    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return FieldIsNotADate(field);
    }
    // `DateTime.tryParse('2026-02-30')` does not fail: it rolls over to the
    // second of March, and so did `new Date()` in the front end this
    // replaces, which is why a birthday of the thirtieth of February used to
    // be accepted. Re-formatting is what catches the rollover.
    if (_asIso(parsed) != value) {
      return FieldIsNotADate(field);
    }

    if (parsed.year < earliestYear) {
      return FieldIsTooOld(field, earliestYear: earliestYear);
    }
    return parsed.isAfter(now()) ? FieldIsInTheFuture(field) : null;
  }

  static String _asIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
