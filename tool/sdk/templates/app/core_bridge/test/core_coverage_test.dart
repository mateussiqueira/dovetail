import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the Rust core offers, against what this bridge passes through.
///
/// The compiler already catches the other direction: a bridge that calls a
/// method the core does not have does not build. The direction nothing
/// catches is the core growing a method and the bridge quietly not exposing
/// it — no error, no warning, just a capability that is missing on the day
/// somebody writes the screen for it.
///
/// This is the SDK gate with the sanity floor lowered: the template ships it
/// with `greaterThan(40)` because a real core has dozens of methods, and a
/// fresh scaffold starts with one. Raise both floors here as the core grows
/// — the point of the floor is only to catch the parser going blind.
///
/// The path points at the sibling `core/` crate the scaffold generated.
const String _corePath = '../core/src/handle.rs';

/// Core methods this bridge deliberately does not pass through, and why.
///
/// A name here is a decision. An empty reason is not allowed, because the
/// point of the list is that the next person can tell an omission from an
/// oversight.
const Map<String, String> _deliberatelyNotExposed = <String, String>{
  'new': 'the constructor; the bridge owns the lifetime through start()',
};

/// The names the bridge holds the core handle under at a call site.
const List<String> _receivers = <String>['core', 'self.inner', 'inner'];

File _coreFile() {
  final File file = File(_corePath);
  return file.isAbsolute ? file : File('${Directory.current.path}/$_corePath');
}

Set<String> _coreMethods(String source) {
  final Set<String> found = <String>{};
  bool inHandle = false;
  for (final String line in source.split('\n')) {
    if (line.startsWith('impl CoreHandle')) {
      inHandle = true;
      continue;
    }
    if (inHandle && line.startsWith('}')) {
      inHandle = false;
      continue;
    }
    if (!inHandle) {
      continue;
    }
    final RegExpMatch? match = RegExp(
      r'^    pub (?:async )?fn ([a-z_0-9]+)\(',
    ).firstMatch(line);
    if (match != null) {
      found.add(match.group(1)!);
    }
  }
  return found;
}

Set<String> _bridgeCalls() {
  final Set<String> found = <String>{};
  final Directory api = Directory('${Directory.current.path}/rust/src/api');
  for (final FileSystemEntity entity in api.listSync()) {
    if (!entity.path.endsWith('.rs')) {
      continue;
    }
    final String source = File(entity.path).readAsStringSync();
    for (final String receiver in _receivers) {
      final RegExp call = RegExp(
        '(?<![A-Za-z0-9_.])${RegExp.escape(receiver)}'
        r'\s*\.([a-z_0-9]+)\(',
      );
      for (final RegExpMatch match in call.allMatches(source)) {
        found.add(match.group(1)!);
      }
    }
  }
  return found;
}

void main() {
  final bool haveCore = _coreFile().existsSync();

  group(
    'the core surface',
    () {
      late Set<String> core;
      late Set<String> bridge;

      setUpAll(() {
        core = _coreMethods(_coreFile().readAsStringSync());
        bridge = _bridgeCalls();
      });

      test('the parse should find something, or it is proving nothing', () {
        expect(
          core,
          hasLength(greaterThan(0)),
          reason:
              'nothing means the `impl CoreHandle` shape changed and every '
              'other assertion here is now vacuous.',
        );
        expect(
          bridge,
          hasLength(greaterThan(0)),
          reason:
              'the bridge reaches the handle under more than one name; zero '
              'means none of them matched',
        );
      });

      test('every core method should reach Dart, or be listed as skipped', () {
        final Set<String> missing = core
            .difference(bridge)
            .difference(_deliberatelyNotExposed.keys.toSet());
        expect(
          missing,
          isEmpty,
          reason:
              'the core grew these and the bridge does not pass them through. '
              'Add them to api/, or add a name and a reason to '
              '_deliberatelyNotExposed.',
        );
      });

      test('the skip list should not outlive the methods it names', () {
        final Set<String> gone = _deliberatelyNotExposed.keys
            .toSet()
            .difference(core);
        expect(
          gone,
          isEmpty,
          reason:
              'these are excused from a surface they are no longer part of, '
              'which is how an excuse starts covering something else',
        );
        for (final MapEntry<String, String> excuse
            in _deliberatelyNotExposed.entries) {
          expect(
            excuse.value.trim(),
            isNotEmpty,
            reason: '"${excuse.key}" is excused with no reason given',
          );
        }
      });

      test('nothing should be both exposed and excused', () {
        expect(
          _deliberatelyNotExposed.keys.toSet().intersection(bridge),
          isEmpty,
          reason: 'the list says these are not passed through, and they are',
        );
      });
    },
    skip: haveCore
        ? null
        : 'no core crate at $_corePath — the bridge init wrote this path '
              'from the --core it got',
  );
}
