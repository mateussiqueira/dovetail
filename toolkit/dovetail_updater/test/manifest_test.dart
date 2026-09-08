import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

const String _static = '''
{
  "version": "1.5.0",
  "notes": "fixes",
  "pub_date": "2026-09-01T12:00:00Z",
  "platforms": {
    "darwin-aarch64": { "signature": "sigA", "url": "https://cdn/a.tar.gz" },
    "windows-x86_64": { "signature": "sigB", "url": "https://cdn/b.exe" },
    "linux-x86_64":   { "signature": "sigC", "url": "https://cdn/c.deb" }
  }
}
''';

const String _dynamic = '''
{ "version": "2.0.0", "url": "https://cdn/x.exe", "signature": "sigX" }
''';

void main() {
  group('the multi platform manifest', () {
    test('should read the version, the notes and the date', () {
      final UpdateManifest sut = ManifestParser.parse(_static);

      expect(sut.version, Version.parse('1.5.0'));
      expect(sut.notes, 'fixes');
      expect(sut.publishedAt, DateTime.utc(2026, 9, 1, 12));
    });

    test('should file every platform under its wire name', () {
      final UpdateManifest sut = ManifestParser.parse(_static);

      expect(
        sut.releases.keys,
        containsAll(<String>[
          'darwin-aarch64',
          'windows-x86_64',
          'linux-x86_64',
        ]),
      );
      expect(sut.releaseFor('windows-x86_64').url, 'https://cdn/b.exe');
    });

    test('should accept a leading v on the version', () {
      expect(
        ManifestParser.parse(
          '{"version":"v3.1.4","platforms":{"a-b":'
          '{"url":"https://x","signature":"s"}}}',
        ).version,
        Version.parse('3.1.4'),
      );
    });

    test('should accept name as an alias for version', () {
      expect(
        ManifestParser.parse(
          '{"name":"1.0.0","platforms":{"a-b":'
          '{"url":"https://x","signature":"s"}}}',
        ).version,
        Version.parse('1.0.0'),
      );
    });

    test('should reject the whole file when one platform block is broken', () {
      const String broken = '''
{
  "version": "1.5.0",
  "platforms": {
    "darwin-aarch64": { "signature": "sigA", "url": "https://cdn/a.tar.gz" },
    "windows-x86_64": { "url": "https://cdn/b.exe" }
  }
}
''';

      expect(
        () => ManifestParser.parse(broken),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('windows-x86_64 has no signature'),
          ),
        ),
        reason:
            'a client on macOS must also refuse this, because a broken block '
            'means the release was published wrong',
      );
    });

    test('should refuse a signature that is a path instead of the content', () {
      const String pathInstead = '''
{"version":"1.0.0","platforms":{"a-b":
{"url":"https://x","signature":"https://cdn/a.sig"}}}
''';

      expect(
        () => ManifestParser.parse(pathInstead),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('silently unverifiable'),
          ),
        ),
      );
    });

    test('should not mistake a real signature for a path', () {
      const String realSignature =
          'RUQhww+7hfwEkWtARB009cGoM/E5aak5XOvFMIgz6fLcTBlqcBJONzflPABPaAHx'
          'nlx5ojvkzJy/zAkxwxHM+kORnis2FsJ2ygw=';

      final UpdateManifest sut = ManifestParser.parse(
        '{"version":"1.0.0","platforms":{"a-b":'
        '{"url":"https://x","signature":"$realSignature"}}}',
      );

      expect(sut.releaseFor('a-b').signature, realSignature);
    });

    test('should refuse a signature that points at a .sig file', () {
      expect(
        () => ManifestParser.parse(
          '{"version":"1.0.0","platforms":{"a-b":'
          '{"url":"https://x","signature":"app.tar.gz.sig"}}}',
        ),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('should refuse an empty platforms map', () {
      expect(
        () => ManifestParser.parse('{"version":"1.0.0","platforms":{}}'),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('should refuse a manifest with no version', () {
      expect(
        () => ManifestParser.parse(
          '{"platforms":{"a-b":'
          '{"url":"https://x","signature":"s"}}}',
        ),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('should refuse a body that is not JSON', () {
      expect(
        () => ManifestParser.parse('<html>404</html>'),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test(
      'releaseFor should name what it does offer when asked for a stranger',
      () {
        final UpdateManifest sut = ManifestParser.parse(_static);

        expect(
          () => sut.releaseFor('linux-riscv64'),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.remedy,
              'remedy',
              contains('darwin-aarch64'),
            ),
          ),
        );
      },
    );
  });

  group('the single platform manifest', () {
    test('should be filed under the key the caller is asking for', () {
      final UpdateManifest sut = ManifestParser.parse(
        _dynamic,
        platformKey: 'windows-x86_64',
      );

      expect(sut.version, Version.parse('2.0.0'));
      expect(sut.releaseFor('windows-x86_64').signature, 'sigX');
    });

    test('should be refused when no key is given to file it under', () {
      expect(
        () => ManifestParser.parse(_dynamic),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('one platform only'),
          ),
        ),
      );
    });
  });

  group('the endpoint template', () {
    const EndpointTemplate sut = EndpointTemplate(
      'https://updates.example.com/{{target}}/{{arch}}/{{bundle_type}}'
      '?from={{current_version}}',
    );

    test('should substitute every placeholder the protocol defines', () {
      expect(
        sut.resolve(
          currentVersion: '1.2.3+build 7',
          target: 'windows',
          arch: 'x86_64',
          bundleType: 'nsis',
        ),
        'https://updates.example.com/windows/x86_64/nsis'
        '?from=1.2.3%2Bbuild%207',
      );
    });

    test(
      'should carry the bundle type, which the Tauri docs never mention',
      () {
        expect(
          sut.resolve(
            currentVersion: '1.0.0',
            target: 'linux',
            arch: 'x86_64',
            bundleType: 'deb',
          ),
          contains('/deb'),
          reason:
              'without it the server cannot tell a .deb install from an '
              'AppImage on the same architecture',
        );
      },
    );

    test('should refuse a placeholder it does not know', () {
      const EndpointTemplate unknown = EndpointTemplate(
        'https://x/{{channel}}',
      );

      expect(
        () => unknown.resolve(
          currentVersion: '1.0.0',
          target: 'linux',
          arch: 'x86_64',
          bundleType: 'deb',
        ),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('should refuse an endpoint that is not https', () {
      const EndpointTemplate insecure = EndpointTemplate('http://x/{{target}}');

      expect(
        () => insecure.resolve(
          currentVersion: '1.0.0',
          target: 'linux',
          arch: 'x86_64',
          bundleType: 'deb',
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('manifest itself is not signed'),
          ),
        ),
      );
    });
  });

  group('the update policy', () {
    const UpdatePolicy sut = UpdatePolicy();

    test('the same version should be up to date', () {
      final UpdateDecision decision = sut.decide(
        installed: Version.parse('1.5.0'),
        manifest: ManifestParser.parse(_static),
      );

      expect(decision.shouldUpdate, false);
    });

    test('a newer version should be offered', () {
      final UpdateDecision decision = sut.decide(
        installed: Version.parse('1.4.9'),
        manifest: ManifestParser.parse(_static),
      );

      expect(decision.shouldUpdate, true);
      expect(decision.offered, Version.parse('1.5.0'));
    });

    test('an older version should be refused, not merely skipped', () {
      expect(
        () => sut.decide(
          installed: Version.parse('1.6.0'),
          manifest: ManifestParser.parse(_static),
        ),
        throwsA(
          isA<DowngradeRefused>()
              .having(
                (DowngradeRefused refused) => refused.remedy,
                'remedy',
                contains('signature alone does not prevent one'),
              )
              .having(
                (DowngradeRefused refused) => refused.offered.toString(),
                'offered',
                '1.5.0',
              )
              .having(
                (DowngradeRefused refused) => refused.installed.toString(),
                'installed',
                '1.6.0',
              ),
        ),
      );
    });

    test('a downgrade should pass when it was asked for on purpose', () {
      const UpdatePolicy permissive = UpdatePolicy(allowDowngrade: true);

      final UpdateDecision decision = permissive.decide(
        installed: Version.parse('1.6.0'),
        manifest: ManifestParser.parse(_static),
      );

      expect(decision.shouldUpdate, true);
    });
  });

  test('the current platform should have a wire name', () {
    expect(PlatformKey.current().wireName, matches(RegExp(r'^\w+-\w+$')));
  });

  group('the universal artefact a publisher may ship instead', () {
    UpdateManifest manifestOffering(List<String> keys) => UpdateManifest(
      version: Version.parse('2.1.0'),
      notes: 'kill switch',
      releases: <String, PlatformRelease>{
        for (final String key in keys)
          key: PlatformRelease(
            url: 'https://cdn/$key.tar.gz',
            signature: 'sig-$key',
          ),
      },
    );

    test('darwin-aarch64 should fall back to darwin-universal', () {
      expect(
        manifestOffering(<String>[
          'darwin-universal',
        ]).releaseFor('darwin-aarch64').url,
        'https://cdn/darwin-universal.tar.gz',
        reason:
            'the CLI documents publishing one fat artefact under that key, and '
            'PlatformKey can only ever ask for os-arch, so without this the '
            'client announces an update it then fails to download',
      );
    });

    test('an exact key should win over the universal one', () {
      expect(
        manifestOffering(<String>[
          'darwin-universal',
          'darwin-aarch64',
        ]).releaseFor('darwin-aarch64').url,
        'https://cdn/darwin-aarch64.tar.gz',
      );
    });

    test('the fallback should not cross operating systems', () {
      expect(
        () => manifestOffering(<String>[
          'darwin-universal',
        ]).releaseFor('windows-x86_64'),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('windows-universal'),
          ),
        ),
      );
    });

    test(
      'neither key should name what is missing without listing what is not',
      () {
        expect(
          () => manifestOffering(<String>[
            'linux-x86_64',
          ]).releaseFor('linux-aarch64'),
          throwsA(
            isA<UpdateFailure>()
                .having(
                  (UpdateFailure failure) => failure.message,
                  'message',
                  contains('linux-aarch64'),
                )
                .having(
                  (UpdateFailure failure) => failure.remedy,
                  'remedy',
                  contains('linux-x86_64'),
                ),
          ),
        );
      },
    );
  });

  _validateGroup();
}

void _validateGroup() {
  group('PlatformKey.validate, the gate a release passes through', () {
    test('every key the protocol can build should be accepted', () {
      for (final UpdateOs os in UpdateOs.values) {
        for (final UpdateArch arch in UpdateArch.values) {
          final String key = '${os.wireName}-${arch.wireName}';
          expect(PlatformKey.validate(key), key);
        }
        expect(
          PlatformKey.validate('${os.wireName}-universal'),
          '${os.wireName}-universal',
        );
      }
    });

    test('the Apple spelling of the arch should be refused by name', () {
      expect(
        () => PlatformKey.validate('darwin-arm64'),
        throwsA(
          isA<UpdateFailure>()
              .having(
                (UpdateFailure f) => f.message,
                'message',
                contains('arm64'),
              )
              .having(
                (UpdateFailure f) => f.remedy,
                'remedy',
                contains('aarch64'),
              ),
        ),
        reason:
            'arm64 is what Apple and WiX call it and aarch64 is what the wire '
            'calls it; a manifest under the wrong one is invisible to clients',
      );
    });

    test('an unknown operating system should be refused', () {
      expect(
        () => PlatformKey.validate('macos-x86_64'),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure f) => f.remedy,
            'remedy',
            contains('darwin'),
          ),
        ),
        reason: 'macos is the directory name; darwin is the platform key',
      );
    });

    test('a key with no divider should be refused', () {
      for (final String bad in <String>['darwin', '-x86_64', 'darwin-', '']) {
        expect(
          () => PlatformKey.validate(bad),
          throwsA(isA<UpdateFailure>()),
          reason: '"$bad"',
        );
      }
    });

    test('an arch carrying a hyphen should still resolve', () {
      expect(
        () => PlatformKey.validate('darwin-x86-64'),
        throwsA(isA<UpdateFailure>()),
        reason:
            'the split takes the first hyphen, so x86-64 reads as one arch '
            'name and is not one the protocol knows',
      );
    });

    test('what current() builds should always validate', () {
      expect(
        PlatformKey.validate(PlatformKey.current().wireName),
        PlatformKey.current().wireName,
      );
    });
  });
}
