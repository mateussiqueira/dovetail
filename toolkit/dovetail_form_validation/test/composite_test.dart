import 'package:dovetail_form_validation/dovetail_form_validation.dart';
import 'package:test/test.dart';

/// The forms the front end this replaces actually built, rebuilt with the
/// builder. They are here as tests rather than as a factory because which
/// form exists is the app's business; what this package owes is that the
/// rules compose the same way.
ValidationComposite _passwordStep() => ValidationComposite(<FieldValidation>[
  ...Field('password').min(8).rules,
  ...Field('passwordConfirmation').sameAs('password').rules,
]);

void main() {
  group('ValidationComposite', () {
    test('should stop at the first failure, in declared order', () {
      final ValidationFailure? failure = _passwordStep().validate(
        <String, String?>{'password': 'short', 'passwordConfirmation': 'other'},
      );
      expect(
        failure,
        isA<FieldIsTooShort>(),
        reason:
            'both rules fail here; a form that shows six messages at once is '
            'one nobody reads to the end',
      );
    });

    test('a valid input should produce no failure at all', () {
      expect(
        _passwordStep().isValid(<String, String?>{
          'password': 'a-long-enough-one',
          'passwordConfirmation': 'a-long-enough-one',
        }),
        isTrue,
      );
    });

    test('no rules should accept anything', () {
      expect(
        const ValidationComposite(
          <FieldValidation>[],
        ).validate(<String, String?>{}),
        isNull,
      );
    });

    test('failuresByField should mark every bad field, one message each', () {
      final Map<String, ValidationFailure> failures =
          ValidationComposite(<FieldValidation>[
            ...Field('name').required().minTrimmed(3).rules,
            ...Field('email').email().rules,
          ]).failuresByField(<String, String?>{'name': '', 'email': 'nope'});

      expect(failures.keys, <String>['name', 'email']);
      expect(
        failures['name'],
        isA<FieldIsRequired>(),
        reason:
            'name breaks two rules; the first one declared is the one worth '
            'saying, because "too short" on an empty field reads as noise',
      );
      expect(failures['email'], isA<FieldIsNotAnEmail>());
    });

    test('failuresByField on a valid input should be empty', () {
      expect(
        _passwordStep().failuresByField(<String, String?>{
          'password': 'a-long-enough-one',
          'passwordConfirmation': 'a-long-enough-one',
        }),
        isEmpty,
      );
    });
  });

  group('Field', () {
    test('should keep the rules in the order they were chained', () {
      expect(
        Field('name')
            .required()
            .minTrimmed(3)
            .rules
            .map((FieldValidation rule) => rule.runtimeType),
        <Type>[RequiredField, MinLength],
      );
    });

    test('every rule should carry the field name it was built for', () {
      for (final FieldValidation rule
          in Field('x')
              .required()
              .min(1)
              .minTrimmed(1)
              .email()
              .sameAs('y')
              .digits(6)
              .pastDate(1900)
              .rules) {
        expect(rule.field, 'x', reason: '${rule.runtimeType}');
      }
    });

    test('the builder should cover all seven rules the product needs', () {
      expect(
        Field('x')
            .required()
            .min(1)
            .minTrimmed(1)
            .email()
            .sameAs('y')
            .digits(6)
            .pastDate(1900)
            .rules,
        hasLength(7),
      );
    });
  });

  group('the failure type', () {
    test('a switch over it should be exhaustive without a default', () {
      // This is the whole reason the failures are a sealed type: the app
      // maps them to text, and adding a rule here has to break that map at
      // compile time rather than fall through to a blank message.
      String messageFor(ValidationFailure failure) => switch (failure) {
        FieldIsRequired() => 'required',
        FieldIsTooShort() => 'too short',
        FieldIsNotAnEmail() => 'not an email',
        FieldIsNotDigits() => 'not digits',
        FieldHasWrongLength() => 'wrong length',
        FieldsDoNotMatch() => 'does not match',
        FieldIsNotADate() => 'not a date',
        FieldIsTooOld() => 'too old',
        FieldIsInTheFuture() => 'in the future',
      };

      expect(messageFor(const FieldIsRequired('a')), 'required');
      expect(
        messageFor(const FieldIsTooShort('a', minimum: 3, actual: 1)),
        'too short',
      );
    });

    test('toString should name the field and the numbers', () {
      expect(
        const FieldIsTooShort('name', minimum: 6, actual: 3).toString(),
        'FieldIsTooShort(name, 3 < 6)',
      );
      expect(
        const FieldHasWrongLength('pin', expected: 6, actual: 5).toString(),
        'FieldHasWrongLength(pin, 5 != 6)',
      );
    });
  });
}
