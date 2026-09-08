import 'package:dovetail_bundler/src/bundle_failure.dart';

enum TargetOs {
  windows('pc-windows-msvc'),
  macos('apple-darwin'),
  linux('unknown-linux-gnu');

  const TargetOs(this.tripleTail);

  final String tripleTail;
}

enum TargetArch {
  x86_64(
    canonical: 'x86_64',
    debian: 'amd64',
    rpm: 'x86_64',
    wix: 'x64',
    apple: 'x86_64',
    triplePrefix: 'x86_64',
    update: 'x86_64',
  ),
  arm64(
    canonical: 'arm64',
    debian: 'arm64',
    rpm: 'aarch64',
    wix: 'arm64',
    apple: 'arm64',
    triplePrefix: 'aarch64',
    update: 'aarch64',
  );

  const TargetArch({
    required this.canonical,
    required this.debian,
    required this.rpm,
    required this.wix,
    required this.apple,
    required this.triplePrefix,
    required this.update,
  });

  final String canonical;
  final String debian;
  final String rpm;
  final String wix;
  final String apple;
  final String triplePrefix;
  final String update;

  String get appImage => update;

  String rustTriple(TargetOs os) => '$triplePrefix-${os.tripleTail}';

  static TargetArch parse(String raw) {
    final String normalized = raw.trim().toLowerCase().replaceAll('-', '_');
    return switch (normalized) {
      'x86_64' || 'x64' || 'amd64' || 'intel' || 'x86 64' => TargetArch.x86_64,
      'arm64' || 'aarch64' || 'armv8' || 'apple_silicon' => TargetArch.arm64,
      'x86' || 'i386' || 'i686' || 'ia32' => throw BundleFailure(
        '32-bit x86 ("$raw") is not a target this bundler builds.',
        remedy:
            'Windows on ARM runs x86_64 under emulation and every supported '
            'desktop is 64-bit. Use x86_64 or arm64.',
      ),
      'armv7' || 'armhf' || 'arm' => throw BundleFailure(
        '32-bit ARM ("$raw") is not a target this bundler builds.',
        remedy: 'Use arm64 for 64-bit ARM.',
      ),
      _ => throw BundleFailure(
        'Architecture "$raw" is not a target this bundler knows.',
        remedy:
            'Use x86_64 (which covers every Intel and AMD desktop — they are '
            'one instruction set, not two targets) or arm64.',
      ),
    };
  }
}
