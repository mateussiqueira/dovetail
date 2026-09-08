import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/src/config/config_failure.dart';

final class UpdateConfig {
  const UpdateConfig({
    required this.keyPath,
    required this.passwordEnv,
    this.publicKey,
    this.baseUrl,
    this.endpoint,
    this.manifestPath = 'dist/latest.json',
    this.unencrypted = false,
  });

  factory UpdateConfig.fromMap(Map<String, Object?> map, String origin) {
    final Object? key = map['key'];
    if (key is! String || key.isEmpty) {
      throw ConfigFailure(
        'update.key is missing.',
        remedy:
            'It is the path to the minisign secret key every installed client '
            'already trusts. Without it a release cannot be signed, and an '
            'unsigned release is one no client will install.',
        origin: origin,
      );
    }

    final Object? baseUrl = map['base-url'];
    if (baseUrl != null && baseUrl is! String) {
      throw ConfigFailure('update.base-url must be a string.', origin: origin);
    }
    if (baseUrl is String && !baseUrl.startsWith('https://')) {
      throw ConfigFailure(
        'update.base-url is "$baseUrl", which is not https.',
        remedy:
            'The updater refuses any other scheme at fetch time, so a base-url '
            'that is not https builds a manifest that cannot be downloaded.',
        origin: origin,
      );
    }

    final Object? publicKey = map['public-key'];
    if (publicKey != null && (publicKey is! String || publicKey.isEmpty)) {
      throw ConfigFailure(
        'update.public-key must be the key itself, as a string.',
        remedy:
            'It is the public half, which every installed client already '
            'carries, so it is safe to commit. A path would be a second file '
            'to keep in step with this one.',
        origin: origin,
      );
    }
    if (publicKey is String) {
      try {
        MinisignPublicKey.parse(publicKey);
      } on UpdateFailure catch (failure) {
        throw ConfigFailure(
          'update.public-key is not a minisign public key: '
          '${failure.message}',
          remedy:
              'Both the plain minisign text and the base64 that Tauri stores '
              'in tauri.conf.json are accepted. Copy it from whichever the '
              'installed clients were built with.',
          origin: origin,
        );
      }
    }

    final Object? manifest = map['manifest'];
    if (manifest != null && manifest is! String) {
      throw ConfigFailure('update.manifest must be a path.', origin: origin);
    }

    final Object? endpoint = map['endpoint'];
    if (endpoint != null && (endpoint is! String || endpoint.isEmpty)) {
      throw ConfigFailure(
        'update.endpoint must be the https url the app asks for the manifest.',
        origin: origin,
      );
    }
    if (endpoint is String && !endpoint.startsWith('https://')) {
      throw ConfigFailure(
        'update.endpoint is "$endpoint", which is not https.',
        remedy:
            'The app refuses any other scheme before opening a socket, so an '
            'endpoint that is not https is one no client ever reaches.',
        origin: origin,
      );
    }

    final Object? passwordEnv = map['password-env'];
    if (passwordEnv != null &&
        (passwordEnv is! String || passwordEnv.isEmpty)) {
      throw ConfigFailure(
        'update.password-env must name an environment variable.',
        origin: origin,
      );
    }

    final Object? unencrypted = map['unencrypted'];
    if (unencrypted != null && unencrypted is! bool) {
      throw ConfigFailure(
        'update.unencrypted must be true or false.',
        remedy:
            'It says the secret key carries no password. An empty password is '
            'never assumed, so saying so is the only way to use one.',
        origin: origin,
      );
    }

    return UpdateConfig(
      keyPath: key,
      unencrypted: unencrypted as bool? ?? false,
      passwordEnv: passwordEnv as String? ?? 'DOVETAIL_UPDATE_KEY_PASSWORD',
      publicKey: publicKey as String?,
      baseUrl: baseUrl as String?,
      endpoint: endpoint as String?,
      manifestPath: manifest as String? ?? 'dist/latest.json',
    );
  }

  final String keyPath;
  final String passwordEnv;

  /// The public half every installed client already trusts, when the project
  /// declares it. A release signed by anything else is one the park refuses,
  /// and refusing it is the only thing that turns that into a build failure
  /// instead of a support call.
  final String? publicKey;

  final String? baseUrl;

  /// Where the SHIPPED APP asks for the manifest — `{{target}}` and the other
  /// placeholders the updater resolves. It lives here so `dovetail build` can
  /// embed it with the public key: one file decides what the app trusts and
  /// where it looks, and a staging build points at a staging host by
  /// changing that file, not the app.
  final String? endpoint;

  final String manifestPath;
  final bool unencrypted;

  String urlFor({required String version, required String fileName}) {
    final String? base = baseUrl;
    if (base == null) {
      throw const ConfigFailure(
        'no update.base-url is configured, so no url can be built.',
        remedy:
            'Either set update.base-url, or pass the full '
            'platformKey=url=path form to --artifact.',
      );
    }
    final String trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$trimmed/$version/$fileName';
  }
}
