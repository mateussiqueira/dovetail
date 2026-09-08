import 'dart:io';

import 'package:dovetail_updater/src/update_failure.dart';

enum UpdateOs {
  linux('linux'),
  darwin('darwin'),
  windows('windows');

  const UpdateOs(this.wireName);

  final String wireName;
}

enum UpdateArch {
  x86('i686'),
  x86_64('x86_64'),
  arm('armv7'),
  aarch64('aarch64'),
  riscv64('riscv64');

  const UpdateArch(this.wireName);

  final String wireName;
}

final class PlatformKey {
  const PlatformKey({required this.os, required this.arch});

  factory PlatformKey.current() =>
      PlatformKey(os: _currentOs(), arch: _currentArch());

  final UpdateOs os;
  final UpdateArch arch;

  String get wireName => '${os.wireName}-${arch.wireName}';

  static const String universalArch = 'universal';

  static String validate(String wireName) {
    final int divider = wireName.indexOf('-');
    if (divider <= 0 || divider == wireName.length - 1) {
      throw UpdateFailure(
        '"$wireName" is not a platform key.',
        remedy:
            'A key is <os>-<arch>, for example ${_vocabulary.take(3).join(', ')}.',
      );
    }

    final String os = wireName.substring(0, divider);
    final String arch = wireName.substring(divider + 1);

    if (!UpdateOs.values.any((UpdateOs known) => known.wireName == os)) {
      throw UpdateFailure(
        '"$os" is not an operating system this protocol names.',
        remedy:
            'It knows ${UpdateOs.values.map((UpdateOs known) => known.wireName).join(', ')}. '
            'A key no client asks for publishes a release nobody can see.',
      );
    }

    final bool known =
        arch == universalArch ||
        UpdateArch.values.any((UpdateArch value) => value.wireName == arch);
    if (!known) {
      throw UpdateFailure(
        '"$arch" is not an architecture this protocol names.',
        remedy:
            'It knows ${UpdateArch.values.map((UpdateArch value) => value.wireName).join(', ')} '
            'and $universalArch. A client asks for its own architecture, so a '
            'key it cannot build is a release it never sees.',
      );
    }

    return wireName;
  }

  static List<String> get _vocabulary => <String>[
    for (final UpdateOs os in UpdateOs.values)
      for (final UpdateArch arch in UpdateArch.values)
        '${os.wireName}-${arch.wireName}',
  ];

  static UpdateOs _currentOs() {
    if (Platform.isLinux) {
      return UpdateOs.linux;
    }
    if (Platform.isMacOS) {
      return UpdateOs.darwin;
    }
    if (Platform.isWindows) {
      return UpdateOs.windows;
    }
    throw UpdateFailure(
      'the update protocol has no name for ${Platform.operatingSystem}.',
    );
  }

  static UpdateArch _currentArch() => archFromAbi(abiOf(Platform.version));

  static UpdateArch archFromAbi(String abi) => switch (abi) {
    'x64' => UpdateArch.x86_64,
    'ia32' => UpdateArch.x86,
    'arm64' => UpdateArch.aarch64,
    'arm' => UpdateArch.arm,
    'riscv64' => UpdateArch.riscv64,
    final String other => throw UpdateFailure(
      'the update protocol has no name for the $other architecture.',
      remedy:
          'Asking for an update under the wrong architecture downloads an '
          'artefact that cannot run, so this refuses instead of guessing.',
    ),
  };

  static String abiOf(String version) {
    final RegExpMatch? match = _abiPattern.firstMatch(version);
    if (match == null) {
      throw UpdateFailure(
        'the running VM did not say which architecture it is on: "$version".',
        remedy:
            'This used to fall back to x64, which on an ARM machine picks the '
            'wrong artefact and reports success until the app will not start.',
      );
    }
    return match.group(2)!;
  }

  static final RegExp _abiPattern = RegExp(r'"([a-z0-9]+)_([a-z0-9]+)"');

  @override
  bool operator ==(Object other) =>
      other is PlatformKey && other.os == os && other.arch == arch;

  @override
  int get hashCode => Object.hash(os, arch);

  @override
  String toString() => wireName;
}
