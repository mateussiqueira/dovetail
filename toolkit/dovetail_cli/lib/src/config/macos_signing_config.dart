import 'package:dovetail_cli/src/config/config_failure.dart';

final class MacosSigningConfig {
  const MacosSigningConfig({
    this.identityEnv = 'DOVETAIL_MACOS_IDENTITY',
    this.entitlements,
    this.notarize = false,
  });

  factory MacosSigningConfig.fromMap(Map<String, Object?> map, String origin) {
    final Object? identityEnv = map['identity-env'];
    if (identityEnv != null &&
        (identityEnv is! String || identityEnv.isEmpty)) {
      throw ConfigFailure(
        'sign.macos.identity-env must name an environment variable.',
        remedy:
            'The identity itself is never written to a file that is committed; '
            'the config names the variable that carries it.',
        origin: origin,
      );
    }

    final Object? entitlements = map['entitlements'];
    if (entitlements != null && entitlements is! String) {
      throw ConfigFailure(
        'sign.macos.entitlements must be a path.',
        origin: origin,
      );
    }

    final Object? notarize = map['notarize'];
    if (notarize != null && notarize is! bool) {
      throw ConfigFailure(
        'sign.macos.notarize must be true or false.',
        origin: origin,
      );
    }

    return MacosSigningConfig(
      identityEnv: identityEnv as String? ?? 'DOVETAIL_MACOS_IDENTITY',
      entitlements: entitlements as String?,
      notarize: notarize as bool? ?? false,
    );
  }

  final String identityEnv;
  final String? entitlements;
  final bool notarize;
}
