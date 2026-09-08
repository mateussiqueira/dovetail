// Imports the i18next JSON the React frontend used into Flutter ARB.
//
// It exists because the strings are the one part of the Tauri app that is
// worth carrying over byte for byte: they were written by people, reviewed
// by people, and shipped. Re-typing them into a new format by hand is how
// a translation quietly loses a word.
//
//   dart run tool/import_locales.dart            # writes the ARB files
//   dart run tool/import_locales.dart --check    # fails if they would change
//
// The tool refuses rather than guesses. Anything it cannot carry over
// without changing what the string says is reported and nothing is written.
import 'dart:convert';
import 'dart:io';

/// Where the React app kept its strings, and what each file becomes.
///
/// `pt-br` is the template: it is the language the strings were written in,
/// so it is the one whose wording the other two answer to. The output drops
/// the country — a reader in Portugal should get the Brazilian text rather
/// than English, and Flutter only falls back by language code.
const Map<String, String> _locales = <String, String>{
  'pt-br': 'pt',
  'en-us': 'en',
  'es-es': 'es',
};

const String _templateLocale = 'pt';

/// The locale whose text becomes each `@key.description`, so that reading
/// the template ARB does not require reading three files at once.
const String _glossSource = 'en-us';

/// Placeholders that name a number. Declared so the generated API takes an
/// `int` and the call site cannot pass a stray string.
const Set<String> _numeric = <String>{
  'n',
  'total',
  'shown',
  'i',
  'max',
  'd',
  'h',
  's',
  'days',
  'current',
};

/// Placeholder names worth fixing on the way in. These never reach a user —
/// they are the argument names of the generated Dart API, which is exactly
/// what someone writing a screen types. `atual` was a Portuguese name left
/// in all three files.
const Map<String, String> _renamed = <String, String>{'atual': 'current'};

final RegExp _placeholder = RegExp(r'\{\{\s*([^}]*?)\s*\}\}');
final RegExp _identifier = RegExp(r'^[a-z][A-Za-z0-9]*$');

/// Members the generated class already has. A key that flattens onto one of
/// these produces Dart that does not compile, and the error points at
/// generated code rather than at the ARB that caused it.
const Set<String> _taken = <String>{
  'localeName',
  'delegate',
  'supportedLocales',
  'of',
  'hashCode',
  'toString',
  'runtimeType',
  'noSuchMethod',
};

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

int _run(List<String> arguments) {
  final bool check = arguments.contains('--check');
  final String from =
      _option(arguments, '--from') ??
      '../example-rust/frontend/src/i18n/locales';
  final String to =
      _option(arguments, '--to') ?? 'product/vpn_desktop/lib/l10n';

  final Directory source = Directory(from);
  if (!source.existsSync()) {
    stderr.writeln('no locale source at ${source.absolute.path}');
    stderr.writeln(
      'this reads the React frontend of example-rust, which is a sibling '
      'checkout. Pass --from if yours lives elsewhere.',
    );
    return 2;
  }

  // Flattened once per locale, keyed by the dotted path from the JSON, so
  // that every later step compares like with like.
  final Map<String, Map<String, String>> read = <String, Map<String, String>>{};
  for (final String name in _locales.keys) {
    final File file = File('$from/$name.json');
    if (!file.existsSync()) {
      stderr.writeln('missing locale file ${file.path}');
      return 2;
    }
    read[name] = _flatten(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
  }

  final List<String> refusals = _refusals(read);
  if (refusals.isNotEmpty) {
    stderr.writeln('nothing was written; ${refusals.length} problem(s):');
    for (final String refusal in refusals) {
      stderr.writeln('  $refusal');
    }
    return 1;
  }

  // A key that is blank in every locale carries no translation and would
  // generate a getter that returns nothing. `settings.onboardingDone` is one
  // of these: it survived in the React JSON with an empty value in all three
  // files. Dropping it loses nothing; keeping it would blunt the test that
  // catches a string someone forgot to write.
  final List<String> blank = read[_glossSource]!.keys
      .where(
        (String key) => read.values.every(
          (Map<String, String> strings) => strings[key]!.trim().isEmpty,
        ),
      )
      .toList();
  for (final String key in blank) {
    stdout.writeln('skipped "$key": blank in every locale');
    for (final Map<String, String> strings in read.values) {
      strings.remove(key);
    }
  }

  final Map<String, String> names = _dartNames(read[_glossSource]!.keys);
  Directory(to).createSync(recursive: true);

  bool drifted = false;
  for (final MapEntry<String, String> locale in _locales.entries) {
    final String rendered = _render(
      locale: locale.value,
      strings: read[locale.key]!,
      gloss: read[_glossSource]!,
      names: names,
      withMetadata: locale.value == _templateLocale,
    );
    final File out = File('$to/app_${locale.value}.arb');
    if (check) {
      final String current = out.existsSync() ? out.readAsStringSync() : '';
      if (current != rendered) {
        stderr.writeln('${out.path} is not what the source would produce');
        drifted = true;
      }
      continue;
    }
    out.writeAsStringSync(rendered);
    stdout.writeln('${out.path}  (${read[locale.key]!.length} messages)');
  }

  return drifted ? 1 : 0;
}

String? _option(List<String> arguments, String name) {
  final int at = arguments.indexOf(name);
  return at >= 0 && at + 1 < arguments.length ? arguments[at + 1] : null;
}

Map<String, String> _flatten(Map<String, Object?> json, [String prefix = '']) {
  final Map<String, String> out = <String, String>{};
  for (final MapEntry<String, Object?> entry in json.entries) {
    final String path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
    final Object? value = entry.value;
    if (value is Map<String, Object?>) {
      out.addAll(_flatten(value, path));
    } else {
      out[path] = '$value';
    }
  }
  return out;
}

/// Everything that would make the import lose or change a string. Collected
/// in full rather than thrown one at a time: someone fixing the source wants
/// the whole list, not a game of whack-a-mole.
List<String> _refusals(Map<String, Map<String, String>> read) {
  final List<String> refusals = <String>[];
  final Map<String, String> template = read[_glossSource]!;

  for (final MapEntry<String, Map<String, String>> locale in read.entries) {
    final Set<String> missing = template.keys.toSet()
      ..removeAll(locale.value.keys);
    final Set<String> extra = locale.value.keys.toSet()
      ..removeAll(template.keys);
    for (final String key in missing) {
      refusals.add('${locale.key}: "$key" is missing');
    }
    for (final String key in extra) {
      refusals.add('${locale.key}: "$key" exists in no other locale');
    }
  }

  for (final String key in template.keys) {
    // A brace that is not part of a {{...}} pair is ICU syntax once the
    // string reaches ARB, and ICU would read it as a placeholder we cannot
    // name. Guessing here changes what the user sees.
    for (final MapEntry<String, Map<String, String>> locale in read.entries) {
      final String? value = locale.value[key];
      if (value == null) {
        continue;
      }
      final String stripped = value.replaceAll(_placeholder, '');
      if (stripped.contains('{') || stripped.contains('}')) {
        refusals.add('${locale.key}: "$key" has a brace outside a placeholder');
      }
    }

    // Blank in some languages and not others is the gap worth shouting
    // about: it reaches a reader as an empty label with no clue why.
    final Iterable<String> empty = read.entries
        .where(
          (MapEntry<String, Map<String, String>> locale) =>
              (locale.value[key] ?? '').trim().isEmpty,
        )
        .map((MapEntry<String, Map<String, String>> locale) => locale.key);
    if (empty.isNotEmpty && empty.length != read.length) {
      refusals.add(
        '"$key" is blank in ${_sorted(empty.toSet())} and not in the rest',
      );
    }

    final Map<String, Set<String>> found = <String, Set<String>>{
      for (final MapEntry<String, Map<String, String>> locale in read.entries)
        locale.key: _placeholdersIn(locale.value[key] ?? ''),
    };
    final Set<String> reference = found[_glossSource]!;
    for (final MapEntry<String, Set<String>> locale in found.entries) {
      if (!_sameSet(locale.value, reference)) {
        refusals.add(
          '${locale.key}: "$key" takes ${_sorted(locale.value)} but '
          '$_glossSource takes ${_sorted(reference)}',
        );
      }
    }
    for (final String name in reference) {
      if (!_identifier.hasMatch(name)) {
        refusals.add('"$key": "$name" is not a usable argument name');
      }
    }
  }

  return refusals..sort();
}

Set<String> _placeholdersIn(String value) => <String>{
  for (final RegExpMatch match in _placeholder.allMatches(value))
    _renamed[match.group(1)!] ?? match.group(1)!,
};

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

String _sorted(Set<String> names) => (names.toList()..sort()).toString();

/// `home.stats.lastHandshake` becomes `homeStatsLastHandshake`. Two paths
/// that collapse onto one name would silently drop a string, so that is an
/// error rather than a last-one-wins.
Map<String, String> _dartNames(Iterable<String> keys) {
  final Map<String, String> names = <String, String>{};
  final Map<String, String> claimed = <String, String>{};
  for (final String key in keys) {
    final List<String> parts = key.split('.');
    final StringBuffer name = StringBuffer(parts.first);
    for (final String part in parts.skip(1)) {
      name
        ..write(part.substring(0, 1).toUpperCase())
        ..write(part.substring(1));
    }
    final String dart = name.toString().replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (claimed.containsKey(dart)) {
      throw StateError('"$key" and "${claimed[dart]}" both become "$dart"');
    }
    if (_taken.contains(dart)) {
      throw StateError('"$key" becomes "$dart", which the class already has');
    }
    claimed[dart] = key;
    names[key] = dart;
  }
  return names;
}

String _render({
  required String locale,
  required Map<String, String> strings,
  required Map<String, String> gloss,
  required Map<String, String> names,
  required bool withMetadata,
}) {
  final Map<String, Object?> arb = <String, Object?>{'@@locale': locale};
  for (final MapEntry<String, String> entry in strings.entries) {
    final String name = names[entry.key]!;
    arb[name] = entry.value.replaceAllMapped(_placeholder, (Match match) {
      final String raw = match.group(1)!;
      return '{${_renamed[raw] ?? raw}}';
    });
    if (!withMetadata) {
      continue;
    }
    final Set<String> placeholders = _placeholdersIn(entry.value);
    arb['@$name'] = <String, Object?>{
      // The dotted path the string had in the React app, so that a string
      // can still be traced back to where it came from, and the English so
      // that the file reads without opening a second one.
      'description': '${entry.key} — ${gloss[entry.key]}',
      if (placeholders.isNotEmpty)
        'placeholders': <String, Object?>{
          for (final String placeholder in _sortedList(placeholders))
            placeholder: <String, Object?>{
              'type': _numeric.contains(placeholder) ? 'int' : 'String',
            },
        },
    };
  }
  return '${const JsonEncoder.withIndent('  ').convert(arb)}\n';
}

List<String> _sortedList(Set<String> names) => names.toList()..sort();
