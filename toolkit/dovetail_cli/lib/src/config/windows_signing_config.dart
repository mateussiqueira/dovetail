import 'package:dovetail_cli/src/config/config_failure.dart';

final class WindowsSigningConfig {
  const WindowsSigningConfig({
    this.certificateEnv = 'DOVETAIL_WINDOWS_CERTIFICATE',
    this.passwordEnv = 'DOVETAIL_WINDOWS_CERTIFICATE_PASSWORD',
    this.timestampUrl,
  });

  factory WindowsSigningConfig.fromMap(
    Map<String, Object?> map,
    String origin,
  ) {
    String named(String field, String fallback) {
      final Object? value = map[field];
      if (value == null) {
        return fallback;
      }
      if (value is! String || value.isEmpty) {
        throw ConfigFailure(
          'sign.windows.$field must name an environment variable.',
          origin: origin,
        );
      }
      return value;
    }

    final Object? timestamp = map['timestamp-url'];
    if (timestamp != null &&
        (timestamp is! String || !timestamp.startsWith('http'))) {
      throw ConfigFailure(
        'sign.windows.timestamp-url must be a url.',
        remedy:
            'Without a timestamp the signature stops verifying the day the '
            'certificate expires, on machines that already installed the app.',
        origin: origin,
      );
    }

    return WindowsSigningConfig(
      certificateEnv: named('certificate-env', 'DOVETAIL_WINDOWS_CERTIFICATE'),
      passwordEnv: named(
        'password-env',
        'DOVETAIL_WINDOWS_CERTIFICATE_PASSWORD',
      ),
      timestampUrl: timestamp as String?,
    );
  }

  final String certificateEnv;
  final String passwordEnv;
  final String? timestampUrl;
}
