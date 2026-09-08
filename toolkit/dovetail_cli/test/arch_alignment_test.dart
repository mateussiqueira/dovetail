import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

UpdateOs _osFor(TargetOs os) => switch (os) {
  TargetOs.windows => UpdateOs.windows,
  TargetOs.macos => UpdateOs.darwin,
  TargetOs.linux => UpdateOs.linux,
};

UpdateArch _archFor(TargetArch arch) => switch (arch) {
  TargetArch.x86_64 => UpdateArch.x86_64,
  TargetArch.arm64 => UpdateArch.aarch64,
};

void main() {
  group('the bundler and the updater must agree on architecture', () {
    test(
      'every TargetArch should have an UpdateArch with the same wire name',
      () {
        for (final TargetArch arch in TargetArch.values) {
          expect(
            _archFor(arch).wireName,
            arch.update,
            reason:
                'the bundler names the artefact and the updater asks for it; a '
                'disagreement ships a file nobody requests',
          );
        }
      },
    );

    test('the six platform keys should match what the bundler would build', () {
      final Set<String> fromUpdater = <String>{};
      final Set<String> fromBundler = <String>{};

      for (final TargetOs os in TargetOs.values) {
        for (final TargetArch arch in TargetArch.values) {
          fromUpdater.add(
            PlatformKey(os: _osFor(os), arch: _archFor(arch)).wireName,
          );
          fromBundler.add('${_wireOsName(os)}-${arch.update}');
        }
      }

      expect(fromBundler, fromUpdater);
      expect(fromUpdater, hasLength(6));
    });

    test('the two enums should cover the same number of architectures', () {
      expect(
        TargetArch.values.map(_archFor).toSet(),
        hasLength(TargetArch.values.length),
        reason: 'two TargetArch mapping to one UpdateArch would collide',
      );
    });

    test(
      'a manifest written for one arch should be asked for by that arch',
      () {
        for (final TargetArch arch in TargetArch.values) {
          final PlatformKey asked = PlatformKey(
            os: UpdateOs.darwin,
            arch: _archFor(arch),
          );
          expect(asked.wireName, 'darwin-${arch.update}');
        }
      },
    );

    test(
      'macos should be darwin on the wire and macos on the command line',
      () {
        expect(_osFor(TargetOs.macos), UpdateOs.darwin);
        expect(
          const PlatformKey(
            os: UpdateOs.darwin,
            arch: UpdateArch.aarch64,
          ).wireName,
          'darwin-aarch64',
          reason:
              'the update protocol inherited darwin from the installed park; '
              'renaming it would orphan every client already out there',
        );
      },
    );
  });
}

String _wireOsName(TargetOs os) => switch (os) {
  TargetOs.windows => 'windows',
  TargetOs.macos => 'darwin',
  TargetOs.linux => 'linux',
};
