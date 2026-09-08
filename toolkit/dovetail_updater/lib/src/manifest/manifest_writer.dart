import 'dart:convert';

import 'package:dovetail_updater/src/manifest/manifest_parser.dart';
import 'package:dovetail_updater/src/minisign/minisign_public_key.dart';
import 'package:dovetail_updater/src/minisign/minisign_signature.dart';
import 'package:dovetail_updater/src/update_failure.dart';
import 'package:pub_semver/pub_semver.dart';

const String _untrustedPrefix = 'untrusted comment:';

final class ManifestEntry {
  const ManifestEntry({
    required this.platformKey,
    required this.url,
    required this.signature,
  });

  final String platformKey;
  final String url;
  final String signature;
}

abstract final class ManifestWriter {
  static String render({
    required String version,
    required List<ManifestEntry> entries,
    String? notes,
  }) {
    final Version parsed = _version(version);
    if (entries.isEmpty) {
      throw const UpdateFailure(
        'a manifest with no platform tells every client there is nothing for '
        'it.',
        remedy: 'Name at least one platform and the artefact it points at.',
      );
    }

    final Map<String, Object?> platforms = <String, Object?>{};
    for (final ManifestEntry entry in entries) {
      if (platforms.containsKey(entry.platformKey)) {
        throw UpdateFailure(
          'the platform "${entry.platformKey}" is given twice.',
          remedy:
              'A manifest holds one artefact per platform, so the second would '
              'silently replace the first and half the clients would download '
              'the wrong file.',
        );
      }
      if (entry.signature.trim().isEmpty) {
        throw UpdateFailure(
          'the signature for "${entry.platformKey}" is empty.',
          remedy:
              'A client refuses an unsigned release, so an empty signature '
              'ships a release nobody can install.',
        );
      }
      if (!entry.url.startsWith('https://')) {
        throw UpdateFailure(
          'the url for "${entry.platformKey}" is not https.',
          remedy:
              'The signature makes tampering detectable, not invisible — but '
              'plain http also leaks which build a machine is running.',
        );
      }
      platforms[entry.platformKey] = <String, Object?>{
        'url': entry.url,
        'signature': _wrapped(entry.signature, entry.platformKey),
      };
    }

    final Map<String, Object?> manifest = <String, Object?>{
      'version': parsed.toString(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes,
      'platforms': platforms,
    };

    final String rendered =
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';

    ManifestParser.parse(rendered);
    return rendered;
  }

  /// The manifest carries the signature as base64 **on top of** the minisign
  /// text. That is what Tauri writes, so it is what every client already in
  /// the field base64-decodes before it parses — a manifest that loses the
  /// layer is a release the installed park refuses, and it refuses it in a
  /// machine nobody here can see.
  ///
  /// Callers hand over either form and the field only ever leaves wrapped, so
  /// there is no caller left that can get the encoding wrong, and no way to
  /// wrap twice.
  static String _wrapped(String signature, String platformKey) {
    try {
      // The raw form is passed through byte for byte, trailing newline and
      // all, because that is what the .minisig holds on disk and what the
      // reference minisign writes. Only the already-wrapped form has to be
      // decoded first, and decoding it is also what keeps this idempotent.
      final String text = signature.trimLeft().startsWith(_untrustedPrefix)
          ? signature
          : MinisignPublicKey.unwrap(signature);
      MinisignSignature.parse(text);
      return base64.encode(utf8.encode(text));
    } on UpdateFailure catch (failure) {
      throw UpdateFailure(
        'the signature for "$platformKey" is not a minisign signature: '
        '${failure.message}',
        remedy:
            'The manifest embeds the contents of the .minisig file, not a '
            'path to it and not a hash of the artefact.',
      );
    }
  }

  static Version _version(String raw) {
    try {
      return Version.parse(raw.trim());
    } on FormatException {
      throw UpdateFailure(
        'the version "$raw" is not a semantic version.',
        remedy:
            'The client compares it against what it has installed. A version '
            'it cannot parse is a manifest it rejects, which reads to the user '
            'as no update ever arriving.',
      );
    }
  }
}
