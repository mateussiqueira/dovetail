import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

void main() {
  PlatformKey key(UpdateOs os, UpdateArch arch) =>
      PlatformKey(os: os, arch: arch);
  PlatformRelease release(String url, String signature) =>
      PlatformRelease(url: url, signature: signature);

  test(
    'platform keys keep operating system and architecture in map identity',
    () {
      final PlatformKey linux = key(UpdateOs.linux, UpdateArch.x86_64);
      expect(
        <PlatformKey, String>{linux: 'artifact'}[key(
          UpdateOs.linux,
          UpdateArch.x86_64,
        )],
        'artifact',
      );
      expect(linux, isNot(key(UpdateOs.windows, UpdateArch.x86_64)));
      expect(linux, isNot(key(UpdateOs.linux, UpdateArch.aarch64)));
      expect(linux, isNot(Object()));
      expect(linux.toString(), 'linux-x86_64');
    },
  );

  test('platform release identity includes the download URL and signature', () {
    final PlatformRelease original = release('https://example.test/app', 'a');
    expect(
      <PlatformRelease>{original}.contains(release(original.url, 'a')),
      true,
    );
    expect(original, isNot(release('https://example.test/other', 'a')));
    expect(original, isNot(release(original.url, 'b')));
    expect(original, isNot(Object()));
  });

  test('update failures include a remedy only when one was supplied', () {
    expect(const UpdateFailure('failed').toString(), 'failed');
    expect(
      const UpdateFailure('failed', remedy: 'retry').toString(),
      'failed\n  retry',
    );
  });

  test(
    'downgrade diagnostics preserve both versions and the refusal reason',
    () {
      final DowngradeRefused failure = DowngradeRefused(
        offered: Version.parse('1.0.0'),
        installed: Version.parse('2.0.0'),
      );
      expect(
        failure.toString(),
        allOf(
          contains('offers 1.0.0 while 2.0.0 is installed'),
          contains('downgrade is refused'),
          contains('signature alone does not prevent one'),
        ),
      );
    },
  );
}
