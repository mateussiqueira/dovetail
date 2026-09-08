import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

void main() {
  group('PlatformKey', () {
    test('should read the abi the vm actually reports', () {
      expect(
        PlatformKey.abiOf('3.12.0 (stable) (Tue Aug 4 2026) on "macos_arm64"'),
        'arm64',
      );
      expect(
        PlatformKey.abiOf('3.12.0 (stable) (Tue Aug 4 2026) on "windows_x64"'),
        'x64',
      );
      expect(
        PlatformKey.abiOf('3.12.0 (stable) (Tue Aug 4 2026) on "linux_arm64"'),
        'arm64',
      );
    });

    test('should refuse a version string it cannot read', () {
      expect(
        () => PlatformKey.abiOf('3.12.0 (stable)'),
        throwsA(isA<UpdateFailure>()),
        reason:
            'the previous reading fell back to x64, which on an arm machine '
            'downloads an x86 artefact and reports success',
      );
    });

    test('an arm host should ask for the aarch64 artefact', () {
      expect(PlatformKey.archFromAbi('arm64'), UpdateArch.aarch64);
      expect(
        const PlatformKey(
          os: UpdateOs.windows,
          arch: UpdateArch.aarch64,
        ).wireName,
        'windows-aarch64',
      );
      expect(
        const PlatformKey(
          os: UpdateOs.linux,
          arch: UpdateArch.aarch64,
        ).wireName,
        'linux-aarch64',
      );
      expect(
        const PlatformKey(
          os: UpdateOs.darwin,
          arch: UpdateArch.aarch64,
        ).wireName,
        'darwin-aarch64',
      );
    });

    test('an intel host should ask for the x86_64 artefact', () {
      expect(PlatformKey.archFromAbi('x64'), UpdateArch.x86_64);
      expect(
        const PlatformKey(
          os: UpdateOs.darwin,
          arch: UpdateArch.x86_64,
        ).wireName,
        'darwin-x86_64',
      );
    });

    test('the six targets should all have a distinct wire name', () {
      final Set<String> names = <String>{
        for (final UpdateOs os in <UpdateOs>[
          UpdateOs.windows,
          UpdateOs.darwin,
          UpdateOs.linux,
        ])
          for (final UpdateArch arch in <UpdateArch>[
            UpdateArch.x86_64,
            UpdateArch.aarch64,
          ])
            PlatformKey(os: os, arch: arch).wireName,
      };
      expect(names, hasLength(6));
    });

    test('an architecture the protocol has no name for should refuse', () {
      expect(
        () => PlatformKey.archFromAbi('sparc64'),
        throwsA(isA<UpdateFailure>()),
      );
    });
  });
}
