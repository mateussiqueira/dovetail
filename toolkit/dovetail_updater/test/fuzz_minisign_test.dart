import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

/// Deterministic fuzz of the minisign parse and verify surface.
///
/// `fuzz_manifest_test.dart` fuzzes the manifest and touches the minisign parse
/// surface only "lightly". This file is the dedicated corpus for the three
/// minisign entry points a hostile body reaches directly:
///
///   * [MinisignSignature.parse] — the 4-line signature (untrusted comment,
///     signature block, trusted comment, global signature);
///   * [MinisignPublicKey.parse] — the comment line plus the 42-byte key line;
///   * [MinisignVerifier.verify] — the trust boundary that turns parsed
///     signature + key + payload into an accept/reject decision.
///
/// The invariant asserted on every input is the same as the manifest fuzz:
/// each call either returns normally or throws the package's own typed
/// [UpdateFailure]. Anything else — a `FormatException`, a `RangeError`, an
/// `Error` — is a finding. An earlier inspection already caught an
/// `ascii.decode` `FormatException` leak exactly at the algorithm-bytes
/// boundary of this parse surface, so the corpus targets that byte position
/// deliberately (both directly and through the double-base64 unwrap).
///
/// Everything below is deterministic: one fixed seed, a fixed iteration count,
/// and no wall-clock or entropy source. A failing input is reported with its
/// seed, strategy and index, plus a hex preview, so it reproduces exactly on
/// re-run.

const int _seed = 0xB16B00; // fixed so a failure reproduces exactly
const int _iterations = 300; // per strategy, sized to stay well under a minute
const int _maxBytes = 2048; // corpus length ceiling for the random-bytes leg

/// The reference-tool fixtures the package already verifies elsewhere, so
/// mutations start from something the parser accepts byte for byte.
const String _signature = '''
untrusted comment: signature from minisign secret key
RUQhww+7hfwEkWtARB009cGoM/E5aak5XOvFMIgz6fLcTBlqcBJONzflPABPaAHxnlx5ojvkzJy/zAkxwxHM+kORnis2FsJ2ygw=
trusted comment: timestamp:1788272466\tfile:small.bin\thashed
pMYx41+3aH2fe3X6jQwLD58C1SBja+rh0FHO+knc/CQedUvUQQhIR7i/l0Ra1N2Djrjm/6XRfpzmnQbF13BGBw==
''';

const String _publicKey = '''
untrusted comment: minisign public key 9104FC85BB0FC321
RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp
''';

/// The payload the reference signature vouches for ("dovetail update payload").
const String _payloadBase64 = 'ZG92ZXRhaWwgdXBkYXRlIHBheWxvYWQ=';
final Uint8List _payload = base64.decode(_payloadBase64);

void main() {
  group('MinisignSignature.parse and MinisignPublicKey.parse', () {
    test('random bytes must be refused or parsed, never crash', () {
      final Random rng = Random(_seed);
      for (int index = 0; index < _iterations; index++) {
        _fuzzMinisign(_randomBytes(rng, 0, _maxBytes), 'random-bytes', index);
      }
    });

    test('mutations of the reference fixtures must be refused or parsed, '
        'never crash', () {
      final Random rng = Random(_seed);
      for (int index = 0; index < _iterations; index++) {
        _fuzzMinisign(_mutateSignature(rng), 'mutated-signature', index);
        _fuzzMinisign(_mutatePublicKey(rng), 'mutated-key', index);
      }
    });

    test('mutations of the double-base64 wrapped form must be refused or '
        'parsed, never crash', () {
      final Random rng = Random(_seed);
      for (int index = 0; index < _iterations; index++) {
        _fuzzMinisign(
          _mutateDoubleEncoded(_signature, rng),
          'mutated-double-signature',
          index,
        );
        _fuzzMinisign(
          _mutateDoubleEncoded(_publicKey, rng),
          'mutated-double-key',
          index,
        );
      }
    });
  });

  group('MinisignVerifier.verify is the trust boundary', () {
    test('parsed fixtures plus random payloads must verify or refuse, never '
        'crash', () {
      final Random rng = Random(_seed);
      for (int index = 0; index < _iterations; index++) {
        _fuzzVerify(_payloadForVerify(rng), 'random-payload', index);
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Fuzz drivers
// ---------------------------------------------------------------------------

/// Runs both minisign parse entries over [input], failing unless each call
/// either succeeds or throws [UpdateFailure].
void _fuzzMinisign(String input, String strategy, int index) {
  final String label = 'seed=$_seed strategy=$strategy index=$index';
  _expectOnlyUpdateFailure(
    '$label (signature)',
    _hexPreview(input),
    () => MinisignSignature.parse(input),
  );
  _expectOnlyUpdateFailure(
    '$label (public key)',
    _hexPreview(input),
    () => MinisignPublicKey.parse(input),
  );
}

/// Runs [MinisignVerifier.verify] over parsed reference fixtures plus a
/// mutated payload, failing unless the call either succeeds or throws
/// [UpdateFailure]. The fixtures are re-parsed per iteration so the verify
/// starts from objects the parser accepts, isolating the verify boundary.
void _fuzzVerify(Uint8List payload, String strategy, int index) {
  final MinisignSignature signature = MinisignSignature.parse(_signature);
  final MinisignPublicKey publicKey = MinisignPublicKey.parse(_publicKey);
  _expectOnlyUpdateFailure(
    'seed=$_seed strategy=$strategy index=$index',
    _hexPreviewBytes(payload),
    () => MinisignVerifier.verify(
      payload: payload,
      signature: signature,
      publicKey: publicKey,
    ),
  );
}

/// The invariant. [parse] may return normally or throw [UpdateFailure]; any
/// other thrown value is a finding, reported with enough context to reproduce.
void _expectOnlyUpdateFailure(
  String label,
  String preview,
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
      '  preview:\n'
      '$preview',
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

/// Mutations of the reference signature: byte flips, truncation, span
/// deletion, line deletion/duplication, blob corruption on either base64 line
/// (with the algorithm bytes forced out of ASCII), line reordering, and junk
/// insertion.
String _mutateSignature(Random rng) {
  switch (rng.nextInt(10)) {
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
    case 6:
      return _corruptBlob(_signature, rng, lineIndex: 3);
    case 7:
      return _corruptAlgorithmBytes(_signature, rng);
    case 8:
      return _reorderLines(_signature, rng);
    default:
      return _insertJunk(_signature, rng);
  }
}

/// Mutations of the reference public key.
String _mutatePublicKey(Random rng) {
  switch (rng.nextInt(8)) {
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
    case 5:
      return _corruptAlgorithmBytes(_publicKey, rng);
    case 6:
      return _reorderLines(_publicKey, rng);
    default:
      return _insertJunk(_publicKey, rng);
  }
}

/// Mutations of the double-base64 wrapped form: corrupt the outer base64 text,
/// or decode the outer layer and corrupt the inner minisign text — including
/// the algorithm bytes — before re-wrapping. This is the path Tauri writes to
/// disk, and the one the field client actually reads.
String _mutateDoubleEncoded(String text, Random rng) {
  final String wrapped = _doubleEncode(text);
  switch (rng.nextInt(6)) {
    case 0:
      return _flipByte(wrapped, rng);
    case 1:
      return _truncate(wrapped, rng);
    case 2:
      return _insertJunk(wrapped, rng);
    case 3:
      return _corruptInnerBlob(text, rng);
    case 4:
      return _corruptInnerAlgorithm(text, rng);
    default:
      return wrapped; // untouched control
  }
}

String _doubleEncode(String text) => base64.encode(utf8.encode(text));

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

/// Decodes a payload line, forces one of its two algorithm bytes outside ASCII
/// (the `ascii.decode` boundary that used to leak a `FormatException`), and
/// re-encodes — base64 stays valid, the algorithm byte does not.
String _corruptAlgorithmBytes(String s, Random rng) {
  final List<String> lines = s.split('\n');
  final int lineIndex = lines.length > 3 ? (rng.nextBool() ? 1 : 3) : 1;
  try {
    final Uint8List blob = base64.decode(lines[lineIndex].trim());
    if (blob.length < 2) {
      return _flipByte(s, rng);
    }
    blob[rng.nextInt(2)] ^= 0xFF;
    lines[lineIndex] = base64.encode(blob);
    return lines.join('\n');
  } on Object {
    return _flipByte(s, rng);
  }
}

/// Decodes the outer base64, corrupts a random byte inside one of the inner
/// base64 payload lines, then re-wraps. Exercises the double-unwrap path with
/// the outer layer still structurally valid.
String _corruptInnerBlob(String text, Random rng) {
  final List<String> lines = text.split('\n');
  final List<int> candidates = lines.length > 3 ? <int>[1, 3] : <int>[1];
  final int lineIndex = candidates[rng.nextInt(candidates.length)];
  try {
    final Uint8List blob = base64.decode(lines[lineIndex].trim());
    if (blob.isEmpty) {
      return _doubleEncode(text);
    }
    blob[rng.nextInt(blob.length)] ^= 1 << rng.nextInt(8);
    lines[lineIndex] = base64.encode(blob);
    return _doubleEncode(lines.join('\n'));
  } on Object {
    return _doubleEncode(text);
  }
}

/// Decodes the outer base64, forces an inner algorithm byte outside ASCII, and
/// re-wraps — the guaranteed algorithm-bytes case through the double-unwrap.
String _corruptInnerAlgorithm(String text, Random rng) {
  final List<String> lines = text.split('\n');
  final int lineIndex = lines.length > 3 ? (rng.nextBool() ? 1 : 3) : 1;
  try {
    final Uint8List blob = base64.decode(lines[lineIndex].trim());
    if (blob.length < 2) {
      return _doubleEncode(text);
    }
    blob[rng.nextInt(2)] ^= 0xFF;
    lines[lineIndex] = base64.encode(blob);
    return _doubleEncode(lines.join('\n'));
  } on Object {
    return _doubleEncode(text);
  }
}

/// A payload for the verify leg: empty, random, the exact reference payload
/// (a control that must verify cleanly), or the reference with a byte flipped.
Uint8List _payloadForVerify(Random rng) {
  switch (rng.nextInt(4)) {
    case 0:
      return Uint8List(0);
    case 1:
      return Uint8List.fromList(
        List<int>.generate(rng.nextInt(_maxBytes + 1), (_) => rng.nextInt(256)),
      );
    case 2:
      return _payload;
    default:
      final Uint8List flipped = Uint8List.fromList(_payload);
      flipped[rng.nextInt(flipped.length)] ^= 1 << rng.nextInt(8);
      return flipped;
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

/// Swaps two lines, so a trusted comment lands where the signature belongs and
/// vice versa — a malformed ordering the parser must refuse, not crash on.
String _reorderLines(String s, Random rng) {
  final List<String> lines = s.split('\n');
  if (lines.length < 2) {
    return s;
  }
  final int i = rng.nextInt(lines.length);
  int j = rng.nextInt(lines.length);
  if (j == i) {
    j = (i + 1) % lines.length;
  }
  final String tmp = lines[i];
  lines[i] = lines[j];
  lines[j] = tmp;
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

String _hexPreview(String input) => _hexPreviewUnits(input.codeUnits);

String _hexPreviewBytes(Uint8List bytes) => _hexPreviewUnits(bytes);

String _hexPreviewUnits(List<int> units) {
  final int limit = units.length < 256 ? units.length : 256;
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < limit; i++) {
    if (i > 0 && i % 32 == 0) {
      buffer.write('\n');
    }
    buffer.write(units[i].toRadixString(16).padLeft(2, '0'));
    buffer.write(' ');
  }
  if (units.length > limit) {
    buffer.write('… (${units.length} bytes total)');
  }
  return buffer.toString();
}
