import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

const String _minimal = '''
identifier: com.example.demo
name: Demo
manufacturer: Example Ltda
targets:
  - darwin-aarch64
''';

DovetailConfig parse(String source) => DovetailConfig.parse(source);

Matcher refusalSaying(Object? message, {Object? remedy}) => throwsA(
  isA<ConfigFailure>()
      .having((ConfigFailure f) => f.message, 'message', message)
      .having(
        (ConfigFailure f) => f.remedy ?? '',
        'remedy',
        remedy ?? anything,
      ),
);

void main() {
  group('the shape it insists on', () {
    test('a minimal config should parse', () {
      final DovetailConfig config = parse(_minimal);

      expect(config.identifier, 'com.example.demo');
      expect(config.name, 'Demo');
      expect(config.targets, <String>['darwin-aarch64']);
      expect(config.update, isNull);
      expect(config.macos, isNull);
    });

    test('a missing identifier should be refused by what needs it', () {
      expect(
        () => parse('name: Demo\ntargets: [darwin-aarch64]\n'),
        refusalSaying(contains('identifier'), remedy: contains('deep-link')),
      );
    });

    test('an identifier that is not reverse-dns should be refused', () {
      for (final String bad in <String>['demo', 'com example', 'com..demo']) {
        expect(
          () => parse('identifier: $bad\nname: D\ntargets: [linux-x86_64]\n'),
          refusalSaying(contains('reverse-dns')),
          reason: bad,
        );
      }
    });

    test('a missing manufacturer should be refused by what needs it', () {
      expect(
        () => parse('identifier: a.b\nname: D\ntargets: [linux-x86_64]\n'),
        refusalSaying(
          contains('manufacturer'),
          remedy: contains('Add or Remove Programs'),
        ),
        reason:
            'every installer format carries it, and there is no sensible '
            'default to invent on the product owner behalf',
      );
    });

    test('a blank name should be refused, not trimmed to nothing', () {
      expect(
        () => parse('identifier: a.b\nname: "  "\ntargets: [linux-x86_64]\n'),
        refusalSaying(contains('name')),
      );
    });

    test('yaml that is not a mapping should say so', () {
      expect(() => parse('- one\n- two\n'), refusalSaying(contains('mapping')));
    });

    test('malformed yaml should name the file, not throw YamlException', () {
      expect(
        () => DovetailConfig.parse('identifier: "unclosed\n', origin: 'x.yaml'),
        throwsA(
          isA<ConfigFailure>().having(
            (ConfigFailure f) => f.origin,
            'origin',
            'x.yaml',
          ),
        ),
      );
    });
  });

  group('targets, which decide what a client can ask for', () {
    test('an empty list should be refused', () {
      expect(
        () => parse('identifier: a.b\nname: D\nmanufacturer: M\ntargets: []\n'),
        refusalSaying(contains('targets')),
      );
    });

    test('a key outside the protocol vocabulary should be refused', () {
      expect(
        () => parse(
          'identifier: a.b\nname: D\nmanufacturer: M\ntargets: [darwin-arm64]\n',
        ),
        refusalSaying(contains('arm64'), remedy: contains('aarch64')),
        reason:
            'arm64 is the Apple spelling and aarch64 is the wire spelling; a '
            'manifest under the wrong one is a release no client ever sees',
      );
    });

    test('an unknown operating system should be refused', () {
      expect(
        () => parse(
          'identifier: a.b\nname: D\nmanufacturer: M\ntargets: [solaris-x86_64]\n',
        ),
        refusalSaying(contains('solaris')),
      );
    });

    test('a universal key should be accepted', () {
      expect(
        parse(
          'identifier: a.b\nname: D\nmanufacturer: M\ntargets: [darwin-universal]\n',
        ).targets,
        <String>['darwin-universal'],
      );
    });

    test('the same target twice should be refused', () {
      expect(
        () => parse(
          'identifier: a.b\nname: D\nmanufacturer: M\ntargets: [linux-x86_64, linux-x86_64]\n',
        ),
        refusalSaying(contains('twice')),
      );
    });

    test('targetsForOs should split by operating system', () {
      final DovetailConfig config = parse('''
identifier: a.b
name: D
manufacturer: M
targets: [darwin-aarch64, darwin-x86_64, linux-x86_64]
''');

      expect(config.targetsForOs('darwin'), hasLength(2));
      expect(config.targetsForOs('linux'), <String>['linux-x86_64']);
      expect(config.targetsForOs('windows'), isEmpty);
    });
  });

  group('the update section', () {
    test('a key path is required once the section exists', () {
      expect(
        () => parse('$_minimal\nupdate:\n  base-url: https://cdn/x\n'),
        refusalSaying(contains('update.key'), remedy: contains('unsigned')),
      );
    });

    test('an endpoint that is not https should be refused', () {
      expect(
        () => parse(
          '$_minimal\nupdate:\n  key: k\n  endpoint: http://api/check/{{target}}\n',
        ),
        refusalSaying(contains('endpoint')),
        reason:
            'o app recusa qualquer outro esquema antes de abrir socket; um '
            'endpoint http e um que nenhum cliente alcanca',
      );
    });

    test('an https endpoint with placeholders should be kept as written', () {
      expect(
        parse(
          '$_minimal\nupdate:\n  key: k\n  endpoint: https://api/check/{{target}}\n',
        ).update!.endpoint,
        'https://api/check/{{target}}',
      );
    });

    test('a base-url that is not https should be refused', () {
      expect(
        () => parse('$_minimal\nupdate:\n  key: k\n  base-url: http://cdn\n'),
        refusalSaying(contains('not https')),
        reason:
            'the fetcher refuses every other scheme, so this would build a '
            'manifest that cannot be downloaded',
      );
    });

    test('defaults should be the ones the commands already used', () {
      final UpdateConfig update = parse(
        '$_minimal\nupdate:\n  key: keys/update.key\n',
      ).update!;

      expect(update.passwordEnv, 'DOVETAIL_UPDATE_KEY_PASSWORD');
      expect(update.manifestPath, 'dist/latest.json');
      expect(update.baseUrl, isNull);
    });

    test('an unencrypted key has to be declared, never inferred', () {
      expect(
        parse('$_minimal\nupdate:\n  key: k\n').update!.unencrypted,
        false,
        reason: 'an empty password is never assumed',
      );
      expect(
        parse(
          '$_minimal\nupdate:\n  key: k\n  unencrypted: true\n',
        ).update!.unencrypted,
        true,
      );
    });

    test('unencrypted must be a boolean, not a string', () {
      expect(
        () => parse('$_minimal\nupdate:\n  key: k\n  unencrypted: "yes"\n'),
        refusalSaying(contains('true or false')),
      );
    });

    test('urlFor should join base, version and file exactly once', () {
      for (final String base in <String>[
        'https://cdn.example.com/releases',
        'https://cdn.example.com/releases/',
      ]) {
        expect(
          parse(
            '$_minimal\nupdate:\n  key: k\n  base-url: $base\n',
          ).update!.urlFor(version: '2.1.0', fileName: 'App.dmg'),
          'https://cdn.example.com/releases/2.1.0/App.dmg',
          reason: base,
        );
      }
    });

    test('urlFor without a base should refuse, not build a relative url', () {
      expect(
        () => parse(
          '$_minimal\nupdate:\n  key: k\n',
        ).update!.urlFor(version: '1.0.0', fileName: 'App.dmg'),
        refusalSaying(contains('base-url')),
      );
    });
  });

  group('the signing section', () {
    test('it should carry variable names, never the identity itself', () {
      final DovetailConfig config = parse('''
$_minimal
sign:
  macos:
    identity-env: MY_IDENTITY
    entitlements: macos/Release.entitlements
    notarize: true
  windows:
    certificate-env: MY_CERT
    timestamp-url: http://timestamp.digicert.com
''');

      expect(config.macos!.identityEnv, 'MY_IDENTITY');
      expect(config.macos!.entitlements, 'macos/Release.entitlements');
      expect(config.macos!.notarize, true);
      expect(config.windows!.certificateEnv, 'MY_CERT');
      expect(config.windows!.timestampUrl, 'http://timestamp.digicert.com');
    });

    test('one platform may be configured without the other', () {
      final DovetailConfig config = parse(
        '$_minimal\nsign:\n  macos:\n    notarize: true\n',
      );

      expect(config.macos, isNotNull);
      expect(config.windows, isNull);
    });

    test('notarize must be a boolean, not a string', () {
      expect(
        () => parse('$_minimal\nsign:\n  macos:\n    notarize: "yes"\n'),
        refusalSaying(contains('true or false')),
      );
    });

    test('a timestamp url that is not a url should be refused', () {
      expect(
        () => parse(
          '$_minimal\nsign:\n  windows:\n    timestamp-url: digicert\n',
        ),
        refusalSaying(contains('timestamp-url'), remedy: contains('expires')),
      );
    });

    test('the windows defaults should name both variables', () {
      final WindowsSigningConfig windows = parse(
        '$_minimal\nsign:\n  windows:\n    timestamp-url: http://t\n',
      ).windows!;

      expect(windows.certificateEnv, 'DOVETAIL_WINDOWS_CERTIFICATE');
      expect(windows.passwordEnv, 'DOVETAIL_WINDOWS_CERTIFICATE_PASSWORD');
    });
  });
}
