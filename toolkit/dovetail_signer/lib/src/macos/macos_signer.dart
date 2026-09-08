import 'package:dovetail_signer/src/macos/sign_target.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_signer/src/signing_failure.dart';
import 'package:path/path.dart' as p;

final class MacosSigningRequest {
  const MacosSigningRequest({
    required this.bundlePath,
    required this.identity,
    this.appEntitlements,
    this.entitlementsByRelativePath = const <String, String>{},
    this.hardenedRuntime = true,
  });

  final String bundlePath;
  final String identity;
  final String? appEntitlements;
  final Map<String, String> entitlementsByRelativePath;
  final bool hardenedRuntime;

  String? entitlementsFor(SignTarget target) {
    if (!target.isExecutable) {
      return null;
    }
    if (target.path == bundlePath) {
      return appEntitlements;
    }
    final String relative = p.relative(target.path, from: bundlePath);
    return entitlementsByRelativePath[relative];
  }
}

final class MacosSigner {
  const MacosSigner({
    required this.runner,
    this.codesign = 'codesign',
    this.xattr = 'xattr',
  });

  final ProcessRunner runner;
  final String codesign;
  final String xattr;

  Future<List<SignTarget>> sign({
    required MacosSigningRequest request,
    required List<String> contents,
  }) async {
    final List<SignTarget> order = SignOrder.insideOut(
      bundlePath: request.bundlePath,
      contents: contents,
    );

    await _stripExtendedAttributes(request.bundlePath);

    for (final SignTarget target in order) {
      final ProcessOutcome outcome = await runner.run(
        codesign,
        argumentsFor(request, target),
      );
      if (!outcome.succeeded) {
        throw SigningFailure(
          'codesign failed on ${target.path} with exit code ${outcome.exitCode}.',
          remedy: outcome.stderr.trim().isEmpty
              ? outcome.stdout.trim()
              : outcome.stderr.trim(),
        );
      }
    }

    return order;
  }

  List<String> argumentsFor(MacosSigningRequest request, SignTarget target) {
    final List<String> arguments = <String>[
      '--force',
      '--timestamp',
      '--sign',
      request.identity,
    ];

    if (request.hardenedRuntime && target.isExecutable) {
      arguments.addAll(<String>['--options', 'runtime']);
    }

    final String? entitlements = request.entitlementsFor(target);
    if (entitlements != null) {
      arguments.addAll(<String>['--entitlements', entitlements]);
    }

    arguments.add(target.path);
    return arguments;
  }

  /// Assina um arquivo plano — o `.dmg` que o usuario baixa. Mesma identidade
  /// e mesmo carimbo; sem `--options runtime`, que e de codigo executavel, e
  /// sem entitlements, que sao do bundle la dentro. O Gatekeeper avalia a
  /// imagem quando ela e montada: um `.app` assinado dentro de um dmg sem
  /// assinatura chega sem assinar a quem baixou, mesmo com Developer ID.
  Future<void> signFile({
    required String path,
    required String identity,
  }) async {
    final ProcessOutcome outcome = await runner.run(
      codesign,
      fileArguments(path: path, identity: identity),
    );
    if (!outcome.succeeded) {
      throw SigningFailure(
        'codesign failed on $path with exit code ${outcome.exitCode}.',
        remedy: outcome.stderr.trim().isEmpty
            ? outcome.stdout.trim()
            : outcome.stderr.trim(),
      );
    }
  }

  List<String> fileArguments({
    required String path,
    required String identity,
  }) => <String>['--force', '--timestamp', '--sign', identity, path];

  Future<void> _stripExtendedAttributes(String bundlePath) async {
    final ProcessOutcome outcome = await runner.run(xattr, <String>[
      '-crs',
      bundlePath,
    ]);
    if (!outcome.succeeded) {
      throw SigningFailure(
        'xattr -crs failed on $bundlePath.',
        remedy:
            'Extended attributes left by a zip or a CI transfer break '
            'codesign. Clear them before signing.',
      );
    }
  }
}
