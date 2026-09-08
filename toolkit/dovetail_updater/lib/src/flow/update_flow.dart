import 'dart:convert';

import 'package:dovetail_updater/src/fetch/artifact_fetcher.dart';
import 'package:dovetail_updater/src/flow/verified_artifact.dart';
import 'package:dovetail_updater/src/manifest/manifest_parser.dart';
import 'package:dovetail_updater/src/manifest/platform_release.dart';
import 'package:dovetail_updater/src/manifest/update_manifest.dart';
import 'package:dovetail_updater/src/minisign/minisign_public_key.dart';
import 'package:dovetail_updater/src/minisign/minisign_signature.dart';
import 'package:dovetail_updater/src/minisign/minisign_verifier.dart';
import 'package:dovetail_updater/src/policy/update_decision.dart';
import 'package:dovetail_updater/src/policy/update_policy.dart';
import 'package:dovetail_updater/src/update_failure.dart';
import 'package:pub_semver/pub_semver.dart';

final class UpdateCheck {
  const UpdateCheck({required this.decision, this.manifest, this.endpoint});

  final UpdateDecision decision;
  final UpdateManifest? manifest;
  final String? endpoint;

  bool get shouldUpdate => decision.shouldUpdate;
}

final class UpdateFlow {
  const UpdateFlow({
    required this.fetcher,
    required this.publicKey,
    required this.platformKey,
    this.policy = const UpdatePolicy(),
  });

  final ArtifactFetcher fetcher;
  final String publicKey;
  final String platformKey;
  final UpdatePolicy policy;

  Future<UpdateCheck> check({
    required List<String> endpoints,
    required Version installed,
  }) async {
    if (endpoints.isEmpty) {
      throw const UpdateFailure('no update endpoint was configured.');
    }

    Object? lastFailure;

    for (final String endpoint in endpoints) {
      final FetchedBody body;
      try {
        body = await fetcher.fetch(Uri.parse(endpoint));
      } on Object catch (error) {
        lastFailure = error;
        continue;
      }

      if (body.isNoContent) {
        return const UpdateCheck(
          decision: UpdateDecision.upToDate('the server answered no content'),
        );
      }
      if (!body.isSuccess) {
        lastFailure = UpdateFailure('$endpoint answered ${body.statusCode}.');
        continue;
      }

      final UpdateManifest manifest = ManifestParser.parse(
        utf8.decode(body.bytes),
        platformKey: platformKey,
      );

      return UpdateCheck(
        decision: policy.decide(installed: installed, manifest: manifest),
        manifest: manifest,
        endpoint: endpoint,
      );
    }

    throw UpdateFailure(
      'every update endpoint failed; the last said: $lastFailure',
      remedy: 'Endpoints are tried in order and the first success wins.',
    );
  }

  Future<VerifiedArtifact> download(
    UpdateManifest manifest, {
    DownloadProgress? onProgress,
  }) async {
    final PlatformRelease release = manifest.releaseFor(platformKey);
    final FetchedBody body = await fetcher.fetch(
      Uri.parse(release.url),
      onProgress: onProgress,
    );

    if (!body.isSuccess) {
      throw UpdateFailure('${release.url} answered ${body.statusCode}.');
    }

    final MinisignSignature signature = MinisignSignature.parse(
      release.signature,
    );

    MinisignVerifier.verify(
      payload: body.bytes,
      signature: signature,
      publicKey: MinisignPublicKey.parse(publicKey),
    );

    return VerifiedArtifact.trusted(
      bytes: body.bytes,
      sourceUrl: release.url,
      trustedComment: signature.trustedComment,
    );
  }
}
