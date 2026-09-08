import 'package:dovetail_form_validation/dovetail_form_validation.dart';
import 'package:test/test.dart';

DateTime Function() _clockAt(String iso) =>
    () => DateTime.parse(iso);

void main() {
  group('RequiredField', () {
    test('should accept anything that is not whitespace', () {
      expect(
        const RequiredField('name').validate(<String, String?>{'name': 'a'}),
        isNull,
      );
    });

    test('an absent key and a null should read the same as an empty one', () {
      for (final Map<String, String?> input in <Map<String, String?>>[
        <String, String?>{},
        <String, String?>{'name': null},
        <String, String?>{'name': ''},
        <String, String?>{'name': '   '},
      ]) {
        expect(
          const RequiredField('name').validate(input),
          isA<FieldIsRequired>(),
          reason: 'for $input',
        );
      }
    });
  });

  group('MinLength', () {
    test('should count the whitespace unless told not to', () {
      const Map<String, String?> input = <String, String?>{'password': '  ab '};
      expect(const MinLength('password', 5).validate(input), isNull);
      expect(
        const MinLength('password', 5, trimmed: true).validate(input),
        isA<FieldIsTooShort>(),
      );
    });

    test(
      'the failure should carry both numbers, so a message can be exact',
      () {
        final ValidationFailure? failure = const MinLength(
          'name',
          6,
        ).validate(<String, String?>{'name': 'abc'});
        expect(failure, isA<FieldIsTooShort>());
        expect((failure! as FieldIsTooShort).minimum, 6);
        expect((failure as FieldIsTooShort).actual, 3);
      },
    );

    test('exactly the minimum should pass', () {
      expect(
        const MinLength('a', 3).validate(<String, String?>{'a': 'abc'}),
        isNull,
      );
    });
  });

  group('Email', () {
    test('should accept the shapes the old front end accepted', () {
      for (final String address in <String>[
        'a@b.co',
        'first.last@sub.domain.com',
        'user+tag@example.org',
        '  spaced@example.com  ',
      ]) {
        expect(
          const Email('email').validate(<String, String?>{'email': address}),
          isNull,
          reason: address,
        );
      }
    });

    test('should refuse the shapes it refused', () {
      for (final String address in <String>[
        '',
        'a@b',
        'a@b.c',
        'no-at-sign.com',
        'two@@example.com',
        'spaced out@example.com',
        '@example.com',
        'a@.com',
      ]) {
        expect(
          const Email('email').validate(<String, String?>{'email': address}),
          isA<FieldIsNotAnEmail>(),
          reason: address,
        );
      }
    });
  });

  group('Digits', () {
    test('should accept exactly the right number of digits', () {
      expect(
        const Digits('pin', 6).validate(<String, String?>{'pin': '012345'}),
        isNull,
      );
    });

    test('the wrong length and the wrong shape should be told apart', () {
      expect(
        const Digits('pin', 6).validate(<String, String?>{'pin': '01234'}),
        isA<FieldHasWrongLength>(),
        reason: 'five digits is a different mistake from a letter',
      );
      expect(
        const Digits('pin', 6).validate(<String, String?>{'pin': '01234a'}),
        isA<FieldIsNotDigits>(),
      );
    });

    test('a sign and a decimal point are not digits', () {
      expect(
        const Digits('pin', 3).validate(<String, String?>{'pin': '+12'}),
        isA<FieldIsNotDigits>(),
      );
      expect(
        const Digits('pin', 3).validate(<String, String?>{'pin': '1.2'}),
        isA<FieldIsNotDigits>(),
      );
    });
  });

  group('SameAs', () {
    test('two equal values should pass', () {
      expect(
        const SameAs('confirmation', 'password').validate(<String, String?>{
          'password': 'secret',
          'confirmation': 'secret',
        }),
        isNull,
      );
    });

    test('the failure should name the field it was compared against', () {
      final ValidationFailure? failure =
          const SameAs('confirmation', 'password').validate(<String, String?>{
            'password': 'secret',
            'confirmation': 'Secret',
          });
      expect(failure, isA<FieldsDoNotMatch>());
      expect((failure! as FieldsDoNotMatch).other, 'password');
      expect(failure.field, 'confirmation');
    });

    test('two absent fields should count as equal, not as an error', () {
      expect(
        const SameAs('a', 'b').validate(<String, String?>{}),
        isNull,
        reason: 'emptiness is what `required` is for, not what this rule is',
      );
    });
  });

  group('PastDate', () {
    final DateTime Function() today = _clockAt('2026-09-03T12:00:00');

    test('a date in the past should pass', () {
      expect(
        PastDate(
          'birthday',
          1900,
          now: today,
        ).validate(<String, String?>{'birthday': '1990-05-17'}),
        isNull,
      );
    });

    test('anything that is not yyyy-MM-dd should be refused as a date', () {
      for (final String value in <String>[
        '',
        '17/05/1990',
        '1990-5-7',
        '1990-05',
        '1990-05-17T00:00:00',
      ]) {
        expect(
          PastDate(
            'birthday',
            1900,
            now: today,
          ).validate(<String, String?>{'birthday': value}),
          isA<FieldIsNotADate>(),
          reason: value,
        );
      }
    });

    test('the thirtieth of February should be refused, not rolled over', () {
      // DateTime.tryParse('2026-02-30') returns the second of March rather
      // than null, and `new Date()` in the front end this replaces did the
      // same — so that birthday used to be accepted, silently, as a
      // different day than the one typed.
      expect(
        PastDate(
          'birthday',
          1900,
          now: today,
        ).validate(<String, String?>{'birthday': '1990-02-30'}),
        isA<FieldIsNotADate>(),
      );
      expect(
        PastDate(
          'birthday',
          1900,
          now: today,
        ).validate(<String, String?>{'birthday': '1990-13-01'}),
        isA<FieldIsNotADate>(),
      );
      expect(
        PastDate(
          'birthday',
          1900,
          now: today,
        ).validate(<String, String?>{'birthday': '1992-02-29'}),
        isNull,
        reason: 'a leap day is a real day',
      );
    });

    test('a year before the earliest should say so, and name it', () {
      final ValidationFailure? failure = PastDate(
        'birthday',
        1900,
        now: today,
      ).validate(<String, String?>{'birthday': '1899-12-31'});
      expect(failure, isA<FieldIsTooOld>());
      expect((failure! as FieldIsTooOld).earliestYear, 1900);
    });

    test('a date in the future should be told apart from a bad one', () {
      expect(
        PastDate(
          'birthday',
          1900,
          now: today,
        ).validate(<String, String?>{'birthday': '2026-09-04'}),
        isA<FieldIsInTheFuture>(),
      );
    });

    test('today should pass, because a birthday today is not the future', () {
      expect(
        PastDate(
          'birthday',
          1900,
          now: today,
        ).validate(<String, String?>{'birthday': '2026-09-03'}),
        isNull,
      );
    });
  });
}
