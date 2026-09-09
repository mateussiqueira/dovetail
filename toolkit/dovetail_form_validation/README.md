**English** · [Português](README.pt-BR.md)

# dovetail_form_validation

> Seven form rules, a builder to compose them, and a failure that says **which
> rule broke** instead of a message the caller has to take on faith.

Pure Dart, no Flutter. 29 tests in under a second.

## Why the failure is not text

The React frontend this was ported from returned a translation key:
`"signup.errors.passwordShort"`. In Dart that does not work — the generated
`AppLocalizations` exposes **getters**, not lookup by string, and there is no
`t('key')`.

The other two options do not serve either. Returning an already-resolved
message forces you to rebuild the validator every time the language changes,
and a validator built once in the controller keeps the old text forever.
Returning a `bool` loses which of the field's two rules failed.

So the failure is a **sealed type**:

```dart
sealed class ValidationFailure { final String field; }

final class FieldIsRequired      extends ValidationFailure {}
final class FieldIsTooShort      extends ValidationFailure { minimum, actual }
final class FieldIsNotAnEmail    extends ValidationFailure {}
final class FieldIsNotDigits     extends ValidationFailure {}
final class FieldHasWrongLength  extends ValidationFailure { expected, actual }
final class FieldsDoNotMatch     extends ValidationFailure { other }
final class FieldIsNotADate      extends ValidationFailure {}
final class FieldIsTooOld        extends ValidationFailure { earliestYear }
final class FieldIsInTheFuture   extends ValidationFailure {}
```

What turns that into a sentence is the screen, with an **exhaustive** `switch`:

```dart
String messageFor(ValidationFailure failure, AppL10n t) => switch (failure) {
  FieldIsRequired()      => t.feedbackRequiredFields,
  FieldIsTooShort()      => t.signupErrorsPasswordShort,
  FieldIsNotAnEmail()    => t.emailInvalid,
  FieldIsNotDigits()     => t.signupErrorsInvalidPin,
  FieldHasWrongLength(:final int expected) => t.emailCodeRequired(expected),
  FieldsDoNotMatch()     => t.signupErrorsPasswordMismatch,
  FieldIsNotADate()      => t.signupErrorsInvalidBirthday,
  FieldIsTooOld()        => t.signupErrorsInvalidBirthday,
  FieldIsInTheFuture()   => t.signupErrorsInvalidBirthday,
};
```

No `default`. Adding a rule here **breaks that `switch` at compile time**,
instead of falling through to empty text in front of someone. And the failure
carries the numbers that produced it, so the message can be *"3 characters
short"* rather than *"too short"*.

The last three point at the same text on purpose: the old frontend gave one
message for a bad date, and separating that is a product decision, not the
port's. **The failure already distinguishes the three**, so the day that
decision is made it costs nothing here.

## Usage

```dart
import 'package:dovetail/dovetail.dart'; // it comes through the barrel

final ValidationComposite password = ValidationComposite(<FieldValidation>[
  ...Field('password').min(8).rules,
  ...Field('passwordConfirmation').sameAs('password').rules,
]);

final ValidationFailure? error = password.validate(<String, String?>{
  'password': controller.text,
  'passwordConfirmation': confirmController.text,
});
```

`validate` stops at the **first** failure, in the order the rules were
declared: a form that shows six messages at once is a form nobody reads to the
end.

When the screen needs to mark every bad field at the same time, and still one
message per field:

```dart
final Map<String, ValidationFailure> byField =
    password.failuresByField(values);
```

## The input map is `Map<String, String?>`

Absent and `null` read as empty. That is what a Flutter form really is —
`TextEditingController.text` — and forcing the caller to normalise it is how a
`null` passes as valid.

## The seven rules

| builder | refuses with |
|---|---|
| `.required()` | `FieldIsRequired` — whitespace only counts as empty |
| `.min(n)` | `FieldIsTooShort` — surrounding whitespace counts |
| `.minTrimmed(n)` | `FieldIsTooShort` — surrounding whitespace does not count |
| `.email()` | `FieldIsNotAnEmail` |
| `.sameAs(other)` | `FieldsDoNotMatch` |
| `.digits(n)` | `FieldHasWrongLength` or `FieldIsNotDigits` |
| `.pastDate(year)` | `FieldIsNotADate`, `FieldIsTooOld` or `FieldIsInTheFuture` |

`min` and `minTrimmed` were two classes in the old frontend; they became one
with a flag, because the only difference between them is whether surrounding
whitespace counts.

## Three things that changed in the port, and why

**The email regexp came across character by character.** Not because it is the
best expression of an address — no regexp is — but because changing it would
start refusing accounts that got in through the old app, and that is a product
decision, not the port's.

**`digits` separates the wrong length from the wrong character.** The old
frontend returned the same key for both. A six-digit PIN typed with five is a
different mistake from one typed with a letter, and whoever typed it deserves
to know which.

**`pastDate` refuses the 30th of February.** `new Date('1990-02-30')` does not
fail: it rolls over to the 2nd of March. `DateTime.tryParse` does exactly the
same. So that birthday **was accepted, silently, as a different day from the
one typed** — and the test that proves it names the old bug. The defence is
reformatting the date and comparing it against what came in.

## What this package does not do

It does not know `AppL10n`, does not know a widget, does not know the product.
It says which rule broke and with what numbers; the sentence belongs to the
screen, and the language to the `l10n`.
