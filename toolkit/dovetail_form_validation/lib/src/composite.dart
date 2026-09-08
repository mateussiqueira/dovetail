import 'failure.dart';
import 'validators.dart';

/// The rules of one form, in the order they were declared.
///
/// It stops at the first failure on purpose: a form that reports six problems
/// at once is a form nobody reads to the end.
final class ValidationComposite {
  const ValidationComposite(this._rules);

  final List<FieldValidation> _rules;

  ValidationFailure? validate(Map<String, String?> input) {
    for (final FieldValidation rule in _rules) {
      final ValidationFailure? failure = rule.validate(input);
      if (failure != null) {
        return failure;
      }
    }
    return null;
  }

  bool isValid(Map<String, String?> input) => validate(input) == null;

  /// The first failure on each field, so a form can mark every bad field at
  /// once while still showing one message per field.
  Map<String, ValidationFailure> failuresByField(Map<String, String?> input) {
    final Map<String, ValidationFailure> found = <String, ValidationFailure>{};
    for (final FieldValidation rule in _rules) {
      final ValidationFailure? failure = rule.validate(input);
      if (failure != null) {
        found.putIfAbsent(failure.field, () => failure);
      }
    }
    return found;
  }
}

/// Builds the rules for one field.
///
///     ValidationComposite(<FieldValidation>[
///       ...Field('name').minTrimmed(3).rules,
///       ...Field('email').email().rules,
///     ]);
final class Field {
  Field(this.name);

  final String name;

  final List<FieldValidation> rules = <FieldValidation>[];

  Field required() => _add(RequiredField(name));

  Field min(int length) => _add(MinLength(name, length));

  Field minTrimmed(int length) => _add(MinLength(name, length, trimmed: true));

  Field email() => _add(Email(name));

  Field sameAs(String other) => _add(SameAs(name, other));

  Field digits(int length) => _add(Digits(name, length));

  Field pastDate(int earliestYear, {DateTime Function() now = DateTime.now}) =>
      _add(PastDate(name, earliestYear, now: now));

  Field _add(FieldValidation rule) {
    rules.add(rule);
    return this;
  }
}
