**English** · [Português](CONTRIBUTING.pt-BR.md)

# Contributing

## What helps most

This project was verified almost entirely on a single machine — one macOS
arm64. The most expensive debt is not a missing feature: it is the absence of
anyone who has run this somewhere else. So, in order of usefulness:

1. **Run it on another operating system and report back.** Windows with MSVC
   and Linux are untested territory. An issue saying "on Windows 11, `dovetail
   doctor` failed like this" is worth more than a feature.
2. **Run the matrix in a fork.** All three legs exist in the workflow and none
   has ever executed, because the account that publishes this repository has
   no Actions. On public repositories Actions is free: forking and letting the
   matrix run already produces the missing information, even if you do not
   change a single line of code.
3. **A feature or a fix.** Welcome, with a test.

## How to run it

Every package under `toolkit/` is independent:

```bash
cd toolkit/<package>
dart pub get        # or flutter pub get, on the packages that depend on Flutter
dart test           # or flutter test
```

The tool comes from the pubspec, not from a guess: `dovetail_cli`,
`dovetail_bundler`, `dovetail_signer`, `dovetail_updater`,
`dovetail_process_runner` and `dovetail_form_validation` are pure Dart, and
`flutter test` on a pure Dart package **hangs** — measured here, `dovetail_cli`
stopped at 441 of 486 tests and never came back, while `dart test` finishes the
same package in 26 seconds.

Each package's `pubspec_overrides.yaml` points at its local neighbours, so
nothing needs to come from pub.dev to develop.

Some tests need a built artefact or a system tool (`codesign`, `minisign`,
`msitools`). They **skip with the reason written out** when it is missing — an
explained skip is not a failure, but it is not a proof either. If one of them
skips on your machine and you do have the tool, that is a bug: report it.

## What the pull request needs to say

- **Which operating system you measured on.** Without that, the most
  important information in the pull request is missing.
- What you saw, not what should happen. "I ran X, Y came out" instead of
  "fixes the behaviour of X".

## Style

- `dart format` before committing. The formatter is the arbiter, no debate.
  The vendored `cargokit/` is excluded on purpose: it comes from an archived
  project and the `cross` gate compares the two copies byte for byte.
- A comment explains **why**, not what the code already says. A comment that
  narrates the line below it is noise; one that records the decision the line
  hides, or the defect it avoids, is the most valuable thing in the file.
- A test that describes the defect it prevents is worth more than a test that
  describes the function.
- Identifiers in English. Comments and documentation may be in Portuguese —
  the project is bilingual about that, and we are not going to translate what
  already exists.

## Documentation

Documentation is bilingual, and both sides are expected to stay complete:

- English lives at the canonical paths — `README.md`, `CONTRIBUTING.md`,
  `docs/*.md`.
- Portuguese lives beside it — `README.pt-BR.md`, `CONTRIBUTING.pt-BR.md`,
  `docs/pt-BR/*.md`.

If you change one side, change the other, or say in the pull request that you
could not. A document that exists in one language only is better than nothing,
but it should be visible that it is half-done rather than silently drift.

## Licence

Contributions come in under the MIT licence, the same as the project.
