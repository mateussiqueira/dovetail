import 'package:dovetail_bundler/dovetail_bundler.dart';

final class TargetKey {
  const TargetKey({required this.platformKey, required this.os, this.arch});

  factory TargetKey.parse(String platformKey) {
    final int divider = platformKey.indexOf('-');
    final String os = platformKey.substring(0, divider);
    final String arch = platformKey.substring(divider + 1);
    return TargetKey(
      platformKey: platformKey,
      os: _bundlerNameFor(os),
      arch: _archFor(arch),
    );
  }

  final String platformKey;
  final String os;
  final TargetArch? arch;

  static const Map<String, String> _bundlerNames = <String, String>{
    'darwin': 'macos',
    'windows': 'windows',
    'linux': 'linux',
  };

  static String _bundlerNameFor(String os) => _bundlerNames[os] ?? os;

  static TargetArch? _archFor(String arch) => switch (arch) {
    'x86_64' => TargetArch.x86_64,
    'aarch64' => TargetArch.arm64,
    _ => null,
  };
}
