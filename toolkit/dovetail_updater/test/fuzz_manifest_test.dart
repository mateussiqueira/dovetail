import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

/// Deterministic fuzz of the update manifest parser — and, lightly, of the
/// minisign parse surface it feeds.
///
/// The manifest is the client's trust boundary: it names what to download and
/// carries the signature that vouches for it. A parser that crashes on
/// malformed input is a denial-of-service vector: any endpoint (or anything
/// posing as one) gets a crash out of a body it fully controls.
///
/// The invariant asserted on every input is therefore: `parse` either returns,
/// or throws the package's own typed [UpdateFailure]. Anything else — a
/// `FormatException`, an `Error` (e.g. a `RangeError` or `StackOverflowError`),
/// or a hang — is a finding. The test framework's own per-test timeout stands
/// in for the "hang" leg of that invariant.
///
/// Everything below is deterministic: one fixed seed, a fixed iteration count,
/// and no wall-clock or entropy source. A failing input is reported with its
/// seed, strategy and index, plus a hex preview of the body, so it reproduces
/// exactly on re-run.

const int _seed = 0xD0E4; // fixed so a failure reproduces exactly
const int _iterations = 300; // per strategy, sized to stay well under a minute
const int _maxBytes = 2048; // corpus length ceiling for the random-bytes leg

/// A real minisign signature (the reference-tool fixture the package already
/// verifies elsewhere), so mutations start from something the parser accepts.
const String _signature =
    'untrusted comment: signature from minisign secret key\n'
    'RUQhww+7hfwEkWtARB009cGoM/E5aak5XOvFMIgz6fLcTBlqcBJONzflPABPaAHxnlx5'
    'ojvkzJy/zAkxwxHM+kORnis2FsJ2ygw=\n'
    'trusted comment: timestamp:1788272466\tfile:small.bin\thashed\n'
    'pMYx41+3aH2fe3X6jQwLD58C1SBja+rh0FHO+knc/CQedUvUQQhIR7i/l0Ra1N2Djrjm'
    '/6XRfpzmnQbF13BGBw==\n';

const String _publicKey =
    'untrusted comment: minisign public key 9104FC85BB0FC321\n'
    'RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp\n';

/// A valid manifest, written by the package's own writer so the mutation leg
/// starts from a document the parser accepts byte for byte, signature already
/// base64-wrapped as a real field does.
final String _validManifest = ManifestWriter.render(
  version: '2.1.0',
  notes: 'kill switch nftables',
  entries: <ManifestEntry>[
    const ManifestEntry(
      platformKey: 'darwin-universal',
      url: 'https://cdn.example.com/app.tar.gz',
      signature: _signature,
    ),
    const ManifestEntry(
      platformKey: 'windows-x86_64',
      url: 'https://cdn.example.com/app.exe',
      signature: _signature,
    ),
  ],
);

void main() {
  group('the manifest parser is the client trust boundary', () {
    test('random bytes must be refused or parsed, never crash', () {
      final Random rng = Random(_seed);
      for (int index = 0; index < _iterations; index++) {
        _fuzzManifest(_randomBytes(rng, 0, _maxBytes), 'random-bytes', index);
      }
    });

    test(
      'random JSON-ish documents must be refused or parsed, never crash',
      () {
        final Random rng = Random(_seed);
        for (int index = 0; index < _iterations; index++) {
          _fuzzManifest(_randomJsonish(rng), 'json-ish', index);
        }
      },
    );

    test(
      'mutations of a valid manifest must be refused or parsed, never crash',
      () {
        final Random rng = Random(_seed);
        for (int index = 0; index < _iterations; index++) {
          _fuzzManifest(_mutateManifest(rng), 'mutated-valid', index);
        }
      },
    );
  });

  group('the minisign parse surface is the signature boundary', () {
    test('random bytes must be refused or parsed, never crash', () {
      final Random rng = Random(_seed);
      for (int index = 0; index < _iterations; index++) {
        _fuzzMinisign(_randomBytes(rng, 0, _maxBytes), 'random-bytes', index);
      }
    });

    test('mutations of a valid signature and public key must be refused or '
        'parsed, never crash', () {
      final Random rng = Random(_seed);
      for (int index = 0; index < _iterations; index++) {
        _fuzzMinisign(_mutateSignature(rng), 'mutated-signature', index);
        _fuzzMinisign(_mutatePublicKey(rng), 'mutated-key', index);
      }
    });
  });
}

/// Runs the manifest parser over [input] both with and without a platform key,
/// failing unless each call either succeeds or throws [UpdateFailure].
void _fuzzManifest(String input, String strategy, int index) {
  _expectOnlyUpdateFailure(
    input,
    'seed=$_seed strategy=$strategy index=$index (no platform key)',
    () => ManifestParser.parse(input),
  );
  _expectOnlyUpdateFailure(
    input,
    'seed=$_seed strategy=$strategy index=$index (platformKey given)',
    () => ManifestParser.parse(input, platformKey: 'windows-x86_64'),
  );
}

/// Runs the minisign parse entries over [input], failing unless each call
/// either succeeds or throws [UpdateFailure].
void _fuzzMinisign(String input, String strategy, int index) {
  _expectOnlyUpdateFailure(
    input,
    'seed=$_seed strategy=$strategy index=$index (signature)',
    () => MinisignSignature.parse(input),
  );
  _expectOnlyUpdateFailure(
    input,
    'seed=$_seed strategy=$strategy index=$index (public key)',
    () => MinisignPublicKey.parse(input),
  );
}

/// The invariant. [parse] may return normally or throw [UpdateFailure]; any
/// other thrown value is a finding, reported with enough context to reproduce.
void _expectOnlyUpdateFailure(
  String input,
  String label,
  void Function() parse,
) {
  try {
    parse();
  } on UpdateFailure {
    return; // the package's own typed failure — the only acceptable one
  } catch (error) {
    fail(
      '$label\n'
      '  threw ${error.runtimeType} instead of UpdateFailure: $error\n'
      '  input (${input.length} code units), hex preview:\n'
      '${_hexPreview(input)}',
    );
  }
}

// ---------------------------------------------------------------------------
// Corpus strategies
// ---------------------------------------------------------------------------

/// Pure random bytes in the range 0..255, built straight from code units so
/// nothing is sanitised before it reaches the parser.
String _randomBytes(Random rng, int minLen, int maxLen) {
  final int length = minLen + rng.nextInt(maxLen - minLen + 1);
  return String.fromCharCodes(
    List<int>.generate(length, (_) => rng.nextInt(256)),
  );
}

/// A random JSON value, biased toward the manifest's real field names, then
/// serialised and — most of the time — corrupted so the document is only
/// "balanced-ish".
String _randomJsonish(Random rng) {
  String text = jsonEncode(_randomJsonValue(rng, 0));
  switch (rng.nextInt(5)) {
    case 0:
      text = _truncate(text, rng);
    case 1:
      text = _deleteSpan(text, rng);
    case 2:
      text = _insertJunk(text, rng);
    case 3:
      text = _flipByte(text, rng);
  }
  return text;
}

const int _maxDepth = 8;

const List<String> _realKeys = <String>[
  'version',
  'name',
  'notes',
  'pub_date',
  'platforms',
  'url',
  'signature',
];

Object? _randomJsonValue(Random rng, int depth) {
  if (depth >= _maxDepth) {
    return _randomScalar(rng);
  }
  switch (rng.nextInt(6)) {
    case 0:
      return _randomScalar(rng);
    case 1:
      return rng.nextInt(1 << 30);
    case 2:
      return rng.nextDouble() * 1000000;
    case 3:
      return rng.nextBool();
    case 4:
      return List<Object?>.generate(
        rng.nextInt(5),
        (_) => _randomJsonValue(rng, depth + 1),
      );
    default:
      final Map<String, Object?> map = <String, Object?>{};
      for (int k = 0; k < rng.nextInt(6); k++) {
        map[_randomFieldName(rng)] = _randomJsonValue(rng, depth + 1);
      }
      return map;
  }
}

String _randomFieldName(Random rng) => rng.nextBool()
    ? _realKeys[rng.nextInt(_realKeys.length)]
    : 'k${rng.nextInt(1000)}';

String _randomScalar(Random rng) {
  final int length = rng.nextInt(16);
  return String.fromCharCodes(
    List<int>.generate(length, (_) {
      switch (rng.nextInt(4)) {
        case 0:
          return 0x20 + rng.nextInt(0x5f); // printable ASCII
        case 1:
          return rng.nextInt(0x20); // control characters, JSON-escaped
        case 2:
          return 0x80 + rng.nextInt(0x40); // non-ASCII latin-1
        default:
          return 0x30 + rng.nextInt(10); // digits
      }
    }),
  );
}

/// A mutation of the valid manifest: byte flips, truncation, span deletion,
/// junk insertion, structured field surgery, duplicate keys, base64-blob
/// corruption, and the untouched document as a control.
String _mutateManifest(Random rng) {
  switch (rng.nextInt(9)) {
    case 0:
      return _flipByte(_validManifest, rng);
    case 1:
      return _truncate(_validManifest, rng);
    case 2:
      return _deleteSpan(_validManifest, rng);
    case 3:
      return _insertJunk(_validManifest, rng);
    case 4:
      return _structuredManifestMutation(rng);
    case 5:
      return _duplicateVersionKey(_validManifest, rng);
    case 6:
      return _corruptBase64Field(_validManifest, rng);
    case 7:
      return _swapFieldType(_validManifest, rng);
    default:
      return _validManifest;
  }
}

/// Structured surgery on the decoded document: delete a field, empty a
/// required one, or set `pub_date` to something that is not a date.
String _structuredManifestMutation(Random rng) {
  final Map<String, Object?> map =
      jsonDecode(_validManifest) as Map<String, Object?>;
  final Map<String, Object?> platforms =
      map['platforms']! as Map<String, Object?>;
  final String key = platforms.keys.first;
  final Map<String, Object?> release = platforms[key]! as Map<String, Object?>;
  switch (rng.nextInt(6)) {
    case 0:
      map.remove('version');
    case 1:
      map.remove('platforms');
    case 2:
      release.remove('signature');
    case 3:
      release.remove('url');
    case 4:
      platforms.clear();
    default:
      map['pub_date'] = 'not a date';
  }
  return jsonEncode(map);
}

/// Swaps a field's type by string surgery on the rendered document: `platforms`
/// becomes a string, `version` becomes a list, `signature` becomes a number.
String _swapFieldType(String s, Random rng) {
  switch (rng.nextInt(3)) {
    case 0:
      return s.replaceFirst('"platforms": {', '"platforms": "nope", "x": {');
    case 1:
      return s.replaceFirst('"version": "', '"version": [');
    default:
      return s.replaceFirst('"signature": "', '"signature": 1234, "s": "');
  }
}

/// Inserts a second `version` key right after the opening brace, the way a
/// hand-written manifest with a duplicated key would.
String _duplicateVersionKey(String s, Random rng) {
  final int brace = s.indexOf('{');
  if (brace < 0) {
    return s;
  }
  final String dup = '"version": "${rng.nextInt(100)}.0.0",';
  return s.substring(0, brace + 1) + dup + s.substring(brace + 1);
}

/// Flips bytes inside the base64 `signature` field value (the parser itself
/// does not decode it, so this is exercised end to end by the minisign leg).
String _corruptBase64Field(String s, Random rng) {
  const String needle = '"signature":"';
  final int start = s.indexOf(needle);
  if (start < 0) {
    return _flipByte(s, rng);
  }
  final int valueStart = start + needle.length;
  final int end = s.indexOf('"', valueStart);
  if (end <= valueStart) {
    return _flipByte(s, rng);
  }
  final List<int> units = s.codeUnits.toList();
  final int i = valueStart + rng.nextInt(end - valueStart);
  units[i] ^= 1 << rng.nextInt(8);
  return String.fromCharCodes(units);
}

/// Mutations of the reference minisign signature: byte flips, truncation,
/// span deletion, line deletion/duplication, junk insertion, and corrupting
/// the signature blob while keeping the base64 structurally valid.
String _mutateSignature(Random rng) {
  switch (rng.nextInt(7)) {
    case 0:
      return _flipByte(_signature, rng);
    case 1:
      return _truncate(_signature, rng);
    case 2:
      return _deleteSpan(_signature, rng);
    case 3:
      return _deleteLine(_signature, rng);
    case 4:
      return _duplicateLine(_signature, rng);
    case 5:
      return _corruptBlob(_signature, rng, lineIndex: 1);
    default:
      return _insertJunk(_signature, rng);
  }
}

/// Mutations of the reference minisign public key.
String _mutatePublicKey(Random rng) {
  switch (rng.nextInt(6)) {
    case 0:
      return _flipByte(_publicKey, rng);
    case 1:
      return _truncate(_publicKey, rng);
    case 2:
      return _deleteSpan(_publicKey, rng);
    case 3:
      return _deleteLine(_publicKey, rng);
    case 4:
      return _corruptBlob(_publicKey, rng, lineIndex: 1);
    default:
      return _insertJunk(_publicKey, rng);
  }
}

/// Decodes one base64 line, flips a byte in the decoded blob, and re-encodes
/// it — the corruption that keeps the outer base64 valid while changing the
/// bytes the parser will inspect.
String _corruptBlob(String s, Random rng, {required int lineIndex}) {
  final List<String> lines = s.split('\n');
  if (lines.length <= lineIndex) {
    return _flipByte(s, rng);
  }
  try {
    final Uint8List blob = base64.decode(lines[lineIndex].trim());
    if (blob.isEmpty) {
      return _flipByte(s, rng);
    }
    blob[rng.nextInt(blob.length)] ^= 1 << rng.nextInt(8);
    lines[lineIndex] = base64.encode(blob);
    return lines.join('\n');
  } on Object {
    return _flipByte(s, rng);
  }
}

// ---------------------------------------------------------------------------
// String mutations
// ---------------------------------------------------------------------------

String _flipByte(String s, Random rng) {
  if (s.isEmpty) {
    return s;
  }
  final List<int> units = s.codeUnits.toList();
  final int i = rng.nextInt(units.length);
  units[i] ^= 1 << rng.nextInt(8);
  return String.fromCharCodes(units);
}

String _truncate(String s, Random rng) {
  if (s.isEmpty) {
    return s;
  }
  return s.substring(0, rng.nextInt(s.length));
}

String _deleteSpan(String s, Random rng) {
  if (s.isEmpty) {
    return s;
  }
  final int start = rng.nextInt(s.length);
  final int length = rng.nextInt(s.length - start);
  return s.replaceRange(start, start + length, '');
}

String _insertJunk(String s, Random rng) {
  final int pos = s.isEmpty ? 0 : rng.nextInt(s.length);
  final String junk = String.fromCharCodes(<int>[rng.nextInt(256)]);
  return s.substring(0, pos) + junk + s.substring(pos);
}

String _deleteLine(String s, Random rng) {
  final List<String> lines = s.split('\n');
  if (lines.length <= 1) {
    return s;
  }
  lines.removeAt(rng.nextInt(lines.length));
  return lines.join('\n');
}

String _duplicateLine(String s, Random rng) {
  final List<String> lines = s.split('\n');
  final int i = rng.nextInt(lines.length);
  lines.insert(i, lines[i]);
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

String _hexPreview(String input) {
  final List<int> units = input.codeUnits;
  final int limit = units.length < 256 ? units.length : 256;
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < limit; i++) {
    if (i > 0 && i % 32 == 0) {
      buffer.write('\n  ');
    }
    buffer.write(units[i].toRadixString(16).padLeft(2, '0'));
    buffer.write(' ');
  }
  if (units.length > limit) {
    buffer.write('… (${units.length} code units total)');
  }
  return buffer.toString();
}
