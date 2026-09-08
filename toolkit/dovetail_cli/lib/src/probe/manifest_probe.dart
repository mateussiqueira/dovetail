import 'dart:convert';
import 'dart:typed_data';

import 'package:dovetail_updater/dovetail_updater.dart';

/// One thing checked, and what came back.
final class ProbeFinding {
  const ProbeFinding({
    required this.what,
    required this.passed,
    required this.detail,
    this.target,
  });

  final String what;
  final bool passed;
  final String detail;

  /// The platform key this is about, when it is about one.
  final String? target;

  @override
  String toString() =>
      '${passed ? 'ok     ' : 'FAILED '}'
      '${target == null ? '' : '$target  '}$what — $detail';
}

final class ProbeReport {
  const ProbeReport(this.findings);

  final List<ProbeFinding> findings;

  bool get passed => findings.every((ProbeFinding finding) => finding.passed);

  int get failures =>
      findings.where((ProbeFinding finding) => !finding.passed).length;
}

/// Asks an endpoint whether it serves something this client can actually use.
///
/// The manifest format is written down in code, in tests, and in prose, and
/// none of those tell whoever implements the server whether the thing they
/// deployed works. This does, from outside, over the wire, using the same
/// parser and the same verifier the shipped app uses — so a green run is not
/// an opinion about the format, it is the client saying yes.
///
/// It is deliberately not part of the app. Whoever writes the endpoint may
/// never touch Dart, and should still be able to run one command and be told
/// what is wrong with what they built.
final class ManifestProbe {
  const ManifestProbe({required this.fetcher});

  final ArtifactFetcher fetcher;

  Future<ProbeReport> run({
    required Uri url,
    required List<String> targets,
    String? publicKey,
    Version? installed,
    bool download = false,
  }) async {
    final List<ProbeFinding> findings = <ProbeFinding>[];

    if (url.scheme != 'https') {
      // Same rule EndpointTemplate enforces, for the same reason: the
      // manifest itself is not signed, so a plain-http endpoint lets anyone
      // between here and there point the client at a different artefact.
      return ProbeReport(<ProbeFinding>[
        ProbeFinding(
          what: 'the endpoint is https',
          passed: false,
          detail:
              '$url is ${url.scheme}. The manifest carries no signature of '
              'its own, so its integrity rests entirely on the transport.',
        ),
      ]);
    }

    final FetchedBody body;
    try {
      body = await fetcher.fetch(url);
    } on Object catch (error) {
      return ProbeReport(<ProbeFinding>[
        ProbeFinding(
          what: 'the endpoint answers',
          passed: false,
          detail: '$error',
        ),
      ]);
    }

    findings.add(
      ProbeFinding(
        what: 'the endpoint answers',
        passed: body.statusCode == 200,
        detail: body.statusCode == 200
            ? '200, ${body.bytes.length} bytes'
            : 'HTTP ${body.statusCode}. A client reads 204 as "nothing new" '
                  'and anything else as broken.',
      ),
    );
    if (body.statusCode != 200) {
      return ProbeReport(findings);
    }

    final UpdateManifest manifest;
    try {
      manifest = ManifestParser.parse(utf8.decode(body.bytes));
    } on Object catch (error) {
      findings.add(
        ProbeFinding(
          what: 'the body parses as a manifest',
          passed: false,
          detail: '$error',
        ),
      );
      return ProbeReport(findings);
    }

    findings.add(
      ProbeFinding(
        what: 'the body parses as a manifest',
        passed: true,
        detail:
            'version ${manifest.version}, '
            '${manifest.releases.length} platform(s): '
            '${manifest.releases.keys.join(', ')}',
      ),
    );

    final MinisignPublicKey? trusted = _trustedKey(publicKey, findings);

    for (final String target in targets) {
      await _checkTarget(
        target: target,
        manifest: manifest,
        trusted: trusted,
        installed: installed,
        download: download,
        findings: findings,
      );
    }

    return ProbeReport(findings);
  }

  MinisignPublicKey? _trustedKey(
    String? publicKey,
    List<ProbeFinding> findings,
  ) {
    if (publicKey == null) {
      findings.add(
        const ProbeFinding(
          what: 'the signing key is checked',
          passed: true,
          detail:
              'no --public-key given, so signatures are checked for shape '
              'only. A manifest signed by the wrong key would pass this run.',
        ),
      );
      return null;
    }
    try {
      final MinisignPublicKey parsed = MinisignPublicKey.parse(publicKey);
      findings.add(
        ProbeFinding(
          what: 'the signing key is checked',
          passed: true,
          detail: 'against key id ${parsed.keyIdHex}',
        ),
      );
      return parsed;
    } on Object catch (error) {
      findings.add(
        ProbeFinding(
          what: 'the signing key is checked',
          passed: false,
          detail: 'the public key given does not parse: $error',
        ),
      );
      return null;
    }
  }

  Future<void> _checkTarget({
    required String target,
    required UpdateManifest manifest,
    required MinisignPublicKey? trusted,
    required Version? installed,
    required bool download,
    required List<ProbeFinding> findings,
  }) async {
    final PlatformRelease release;
    try {
      release = manifest.releaseFor(target);
    } on Object catch (error) {
      findings.add(
        ProbeFinding(
          target: target,
          what: 'the manifest offers this platform',
          passed: false,
          detail: '$error',
        ),
      );
      return;
    }

    findings.add(
      ProbeFinding(
        target: target,
        what: 'the manifest offers this platform',
        passed: true,
        detail: release.url,
      ),
    );

    final Uri artifact = Uri.parse(release.url);
    findings.add(
      ProbeFinding(
        target: target,
        what: 'the download url is https',
        passed: artifact.scheme == 'https',
        detail: artifact.scheme == 'https'
            ? artifact.host
            : 'it is ${artifact.scheme}',
      ),
    );

    final MinisignSignature? signature = _signatureOf(
      target: target,
      release: release,
      findings: findings,
    );
    if (signature == null) {
      return;
    }

    if (trusted != null) {
      final bool matches = signature.keyIdHex == trusted.keyIdHex;
      findings.add(
        ProbeFinding(
          target: target,
          what: 'the signature is by the key this client trusts',
          passed: matches,
          detail: matches
              ? signature.keyIdHex
              : 'signed by ${signature.keyIdHex}, and the client trusts '
                    '${trusted.keyIdHex}. Every install would refuse this '
                    'release.',
        ),
      );
      if (!matches) {
        return;
      }
    }

    if (installed != null) {
      final UpdateDecision decision = const UpdatePolicy().decide(
        installed: installed,
        manifest: manifest,
      );
      findings.add(
        ProbeFinding(
          target: target,
          what: 'the policy would offer this to $installed',
          passed: decision.shouldUpdate,
          detail: decision.shouldUpdate
              ? '${manifest.version} is newer'
              : 'it would not: ${decision.availability.name}',
        ),
      );
    }

    if (download) {
      await _verifyArtifact(
        target: target,
        artifact: artifact,
        signature: signature,
        trusted: trusted,
        findings: findings,
      );
    }
  }

  MinisignSignature? _signatureOf({
    required String target,
    required PlatformRelease release,
    required List<ProbeFinding> findings,
  }) {
    // Deliberately base64 first, with no fallback, because that is what a
    // client in the field does. Going through MinisignSignature.parse would
    // accept the raw text too, and accepting both is exactly what let a
    // release ship the form no client reads.
    final String text;
    try {
      text = utf8.decode(base64.decode(release.signature));
    } on Object {
      findings.add(
        ProbeFinding(
          target: target,
          what: 'the signature field decodes',
          passed: false,
          detail:
              'it is not base64. The field carries base64 over the minisign '
              'text, never the text itself — a client decodes before it '
              'parses, and finds out on a machine nobody here can see.',
        ),
      );
      return null;
    }

    try {
      final MinisignSignature parsed = MinisignSignature.parse(text);
      findings.add(
        ProbeFinding(
          target: target,
          what: 'the signature field decodes',
          passed: true,
          detail:
              'key ${parsed.keyIdHex}, '
              'trusted comment "${parsed.trustedComment}"',
        ),
      );
      return parsed;
    } on Object catch (error) {
      findings.add(
        ProbeFinding(
          target: target,
          what: 'the signature field decodes',
          passed: false,
          detail: 'it decoded, and what came out is not minisign: $error',
        ),
      );
      return null;
    }
  }

  Future<void> _verifyArtifact({
    required String target,
    required Uri artifact,
    required MinisignSignature signature,
    required MinisignPublicKey? trusted,
    required List<ProbeFinding> findings,
  }) async {
    if (trusted == null) {
      findings.add(
        ProbeFinding(
          target: target,
          what: 'the artefact verifies',
          passed: false,
          detail:
              '--download needs --public-key: verifying against the key that '
              'signed it proves only that the two came from the same place.',
        ),
      );
      return;
    }

    final Uint8List bytes;
    try {
      bytes = (await fetcher.fetch(artifact)).bytes;
    } on Object catch (error) {
      findings.add(
        ProbeFinding(
          target: target,
          what: 'the artefact downloads',
          passed: false,
          detail: '$error',
        ),
      );
      return;
    }

    findings.add(
      ProbeFinding(
        target: target,
        what: 'the artefact downloads',
        passed: true,
        detail: '${bytes.length} bytes',
      ),
    );

    try {
      MinisignVerifier.verify(
        payload: bytes,
        signature: signature,
        publicKey: trusted,
      );
      findings.add(
        ProbeFinding(
          target: target,
          what: 'the artefact verifies',
          passed: true,
          detail: 'the bytes served are the bytes signed',
        ),
      );
    } on Object catch (error) {
      findings.add(
        ProbeFinding(
          target: target,
          what: 'the artefact verifies',
          passed: false,
          detail:
              'the signature does not cover what the url serves: $error. '
              'Every install would refuse it.',
        ),
      );
    }
  }
}
