import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late CommandRunner<int> runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_signcmd');
    runner = CommandRunner<int>('dovetail', 'test')..addCommand(SignCommand());
  });

  tearDown(() => root.deleteSync(recursive: true));

  String artifactAt(String name) {
    final String path = p.join(root.path, name);
    File(path).writeAsStringSync('bytes of $name');
    return path;
  }

  group('the target it was given', () {
    test(
      'macos without a bundle or a file should be refused, naming both',
      () async {
        await expectLater(
          runner.run(<String>['sign', '--target', 'macos']),
          throwsA(
            isA<UsageException>().having(
              (UsageException error) => error.message,
              'message',
              allOf(contains('--bundle'), contains('--file')),
            ),
          ),
        );
      },
    );

    test('an unknown target should be refused', () async {
      await expectLater(
        runner.run(<String>['sign', '--target', 'solaris']),
        throwsA(isA<UsageException>()),
      );
    });

    test(
      'macos with no identity in the environment should skip, not sign',
      () async {
        final String bundle = p.join(root.path, 'Example.app');
        Directory(bundle).createSync();

        expect(
          await runner.run(<String>[
            'sign',
            '--target',
            'macos',
            '--bundle',
            bundle,
          ]),
          0,
          reason:
              'a local build without a Developer ID is not an error, it is an '
              'unsigned build, and the note says so',
        );
      },
    );

    test(
      'macos with require-signature and no identity should refuse',
      () async {
        final String bundle = p.join(root.path, 'Example.app');
        Directory(bundle).createSync();

        await expectLater(
          runner.run(<String>[
            'sign',
            '--target',
            'macos',
            '--bundle',
            bundle,
            '--require-signature',
          ]),
          throwsA(
            isA<SigningFailure>().having(
              (SigningFailure failure) => failure.remedy,
              'remedy',
              contains('--require-signature'),
            ),
          ),
        );
      },
    );

    test('macos with both --bundle and --file should be refused', () async {
      final String bundle = p.join(root.path, 'Example.app');
      Directory(bundle).createSync();
      final String dmg = artifactAt('Example.dmg');

      await expectLater(
        runner.run(<String>[
          'sign',
          '--target',
          'macos',
          '--bundle',
          bundle,
          '--file',
          dmg,
        ]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('not both'),
          ),
        ),
      );
    });

    test('macos --file that is not on disk should be refused before any '
        'credential verdict', () async {
      await expectLater(
        runner.run(<String>[
          'sign',
          '--target',
          'macos',
          '--file',
          p.join(root.path, 'nao', 'existe.dmg'),
        ]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('no artefact at'),
          ),
        ),
      );
    });

    test('macos --file with no identity should skip, not sign', () async {
      final String dmg = artifactAt('Example.dmg');

      expect(
        await runner.run(<String>['sign', '--target', 'macos', '--file', dmg]),
        0,
        reason:
            'o ship planejava este passo e o comando o recusava com "macos '
            'needs --bundle": a esteira morria no quarto de cinco passos',
      );
    });

    test(
      'macos --file with require-signature and no identity should refuse',
      () async {
        final String dmg = artifactAt('Example.dmg');

        await expectLater(
          runner.run(<String>[
            'sign',
            '--target',
            'macos',
            '--file',
            dmg,
            '--require-signature',
          ]),
          throwsA(isA<SigningFailure>()),
        );
      },
    );

    test('windows with no certificate should skip, not sign', () async {
      expect(
        await runner.run(<String>[
          'sign',
          '--target',
          'windows',
          '--file',
          artifactAt('setup.exe'),
        ]),
        0,
      );
    });

    test(
      'windows with require-signature and no certificate should refuse',
      () async {
        await expectLater(
          runner.run(<String>[
            'sign',
            '--target',
            'windows',
            '--file',
            artifactAt('setup.exe'),
            '--require-signature',
          ]),
          throwsA(isA<SigningFailure>()),
        );
      },
    );

    test('linux should write the checksums beside the artefacts', () async {
      if (Process.runSync('which', <String>['shasum']).exitCode != 0) {
        markTestSkipped('shasum is not installed');
        return;
      }

      final String first = artifactAt('client_1.0.0_amd64.deb');
      final String second = artifactAt('client-1.0.0-1.x86_64.rpm');

      expect(
        await runner.run(<String>[
          'sign',
          '--target',
          'linux',
          '--file',
          first,
          '--file',
          second,
          '--out-dir',
          root.path,
        ]),
        0,
      );

      final File sums = File(p.join(root.path, 'SHA256SUMS'));
      expect(sums.existsSync(), true);
      expect(sums.readAsStringSync(), contains('client_1.0.0_amd64.deb'));
      expect(sums.readAsStringSync(), contains('client-1.0.0-1.x86_64.rpm'));

      expect(
        Process.runSync('shasum', <String>[
          '-a',
          '256',
          '-c',
          'SHA256SUMS',
        ], workingDirectory: root.path).exitCode,
        0,
        reason: 'the file it wrote has to check against the files it named',
      );
    });

    test('linux should refuse an artefact from another directory', () async {
      if (Process.runSync('which', <String>['shasum']).exitCode != 0) {
        markTestSkipped('shasum is not installed');
        return;
      }

      final String inside = artifactAt('client.deb');
      final Directory elsewhere = Directory(p.join(root.path, 'other'))
        ..createSync();
      final String outside = p.join(elsewhere.path, 'stray.rpm');
      File(outside).writeAsStringSync('x');

      await expectLater(
        runner.run(<String>[
          'sign',
          '--target',
          'linux',
          '--file',
          inside,
          '--file',
          outside,
          '--out-dir',
          root.path,
        ]),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            contains('shasum -c cannot resolve'),
          ),
        ),
      );
    });

    test('linux with no file should be refused', () async {
      await expectLater(
        runner.run(<String>[
          'sign',
          '--target',
          'linux',
          '--out-dir',
          root.path,
        ]),
        throwsA(isA<SigningFailure>()),
      );
    });
  });

  group('the notarize flag', () {
    test('should be declared and read, not declared and ignored', () async {
      final String bundle = p.join(root.path, 'Example.app');
      Directory(bundle).createSync();

      expect(
        await runner.run(<String>[
          'sign',
          '--target',
          'macos',
          '--bundle',
          bundle,
          '--notarize',
        ]),
        0,
        reason:
            'without an identity the signing step skips before notarisation '
            'is reached, and that path has to complete rather than crash',
      );
    });
  });

  group('the dmg path, with an identity and a recording runner', () {
    const Map<String, String> identity = <String, String>{
      'APPLE_SIGNING_IDENTITY': 'Developer ID Application: Example',
    };
    const Map<String, String> notary = <String, String>{
      'APPLE_ID': 'someone@example.com',
      'APPLE_PASSWORD': 'app-specific',
      'APPLE_TEAM_ID': 'TEAM123',
    };

    CommandRunner<int> signing(_Recording recording, Map<String, String> env) =>
        CommandRunner<int>('dovetail', 'test')
          ..addCommand(SignCommand(runner: recording, environment: env));

    test('should reach codesign as a flat file: identity and timestamp, no '
        'runtime, no entitlements', () async {
      final _Recording recording = _Recording();
      final String dmg = artifactAt('Example.dmg');

      expect(
        await signing(
          recording,
          identity,
        ).run(<String>['sign', '--target', 'macos', '--file', dmg]),
        0,
      );

      expect(recording.calls, hasLength(1));
      expect(recording.calls.single, <String>[
        'codesign',
        '--force',
        '--timestamp',
        '--sign',
        'Developer ID Application: Example',
        dmg,
      ]);
    });

    test('--notarize should submit the dmg itself and staple it, with no '
        'ditto', () async {
      final _Recording recording = _Recording();
      final String dmg = artifactAt('Example.dmg');

      expect(
        await signing(recording, <String, String>{...identity, ...notary}).run(
          <String>['sign', '--target', 'macos', '--file', dmg, '--notarize'],
        ),
        0,
      );

      final List<String> tools = recording.calls
          .map((List<String> call) => call.first)
          .toList();
      expect(tools, isNot(contains('ditto')));
      final List<String> submit = recording.calls.firstWhere(
        (List<String> call) => call.contains('submit'),
      );
      expect(submit, contains(dmg));
      expect(
        recording.calls
            .firstWhere((List<String> call) => call.contains('staple'))
            .last,
        'Example.dmg',
      );
    });

    test('--notarize with --require-signature and no notary credentials '
        'should refuse, naming both groups', () async {
      final _Recording recording = _Recording();
      final String dmg = artifactAt('Example.dmg');

      await expectLater(
        signing(recording, identity).run(<String>[
          'sign',
          '--target',
          'macos',
          '--file',
          dmg,
          '--notarize',
          '--require-signature',
        ]),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            allOf(contains('APPLE_ID'), contains('APPLE_API_KEY_ID')),
          ),
        ),
        reason:
            'um ship com notarize: true e sem credenciais Apple saia 0 dizendo '
            '"nothing was submitted" — verde sobre um dmg que o Gatekeeper recusa',
      );
    });

    test(
      '--file that is a directory should be refused: a bundle is --bundle',
      () async {
        final _Recording recording = _Recording();
        final String app = p.join(root.path, 'Example.app');
        Directory(app).createSync();

        await expectLater(
          signing(
            recording,
            identity,
          ).run(<String>['sign', '--target', 'macos', '--file', app]),
          throwsA(
            isA<UsageException>().having(
              (UsageException error) => error.message,
              'message',
              contains('is a directory'),
            ),
          ),
        );
        expect(recording.calls, isEmpty);
      },
    );

    test(
      '--bundle with --entitlements should hand the plist to codesign',
      () async {
        final _Recording recording = _Recording();
        final String app = p.join(root.path, 'Example.app');
        Directory(app).createSync();
        final String plist = artifactAt('Release.entitlements');

        expect(
          await signing(recording, identity).run(<String>[
            'sign',
            '--target',
            'macos',
            '--bundle',
            app,
            '--entitlements',
            plist,
          ]),
          0,
        );

        final List<String> codesign = recording.calls.firstWhere(
          (List<String> call) => call.first == 'codesign',
        );
        expect(codesign, containsAllInOrder(<String>['--entitlements', plist]));
      },
    );
  });

  group('the entitlements the app step applies by default', () {
    late Directory project;

    setUp(() => project = Directory.systemTemp.createTempSync('sign_ent'));
    tearDown(() => project.deleteSync(recursive: true));

    // A forma que o Xcode escreve: um bloco XCBuildConfiguration por
    // configuracao, com buildSettings e o `name` no fim.
    void pbxproj(List<({String name, String plist})> configurations) {
      final Directory xcodeproj = Directory(
        p.join(project.path, 'macos', 'Runner.xcodeproj'),
      )..createSync(recursive: true);
      final StringBuffer out = StringBuffer();
      for (final ({String name, String plist}) each in configurations) {
        out.write(
          '\t\t0000 /* ${each.name} */ = {\n'
          '\t\t\tisa = XCBuildConfiguration;\n'
          '\t\t\tbuildSettings = {\n'
          '\t\t\t\tCODE_SIGN_ENTITLEMENTS = ${each.plist};\n'
          '\t\t\t\tPRODUCT_NAME = "\$(TARGET_NAME)";\n'
          '\t\t\t};\n'
          '\t\t\tname = ${each.name};\n'
          '\t\t};\n',
        );
      }
      File(
        p.join(xcodeproj.path, 'project.pbxproj'),
      ).writeAsStringSync(out.toString());
    }

    void plist(String relative) {
      File(p.join(project.path, 'macos', relative))
        ..createSync(recursive: true)
        ..writeAsStringSync('<plist/>');
    }

    test('should pick the plist of the RELEASE configuration, whatever its '
        'file name', () {
      // Pela configuracao, nao pelo nome: o Xcode reaponta a chave quando
      // alguem mexe em Signing & Capabilities, e o plist de Release pode se
      // chamar Runner.entitlements. Adivinhar pelo nome aplicaria um velho.
      pbxproj(<({String name, String plist})>[
        (name: 'Debug', plist: 'Runner/DebugProfile.entitlements'),
        (name: 'Profile', plist: 'Runner/DebugProfile.entitlements'),
        (name: 'Release', plist: 'Runner/Prod.entitlements'),
      ]);
      plist('Runner/DebugProfile.entitlements');
      plist('Runner/Prod.entitlements');
      plist('Runner/Release.entitlements');

      final ({String path, String source})? found =
          SignCommand.defaultEntitlements(project.path);

      expect(
        found?.path,
        p.join(project.path, 'macos', 'Runner/Prod.entitlements'),
      );
      expect(found?.source, contains('Release configuration'));
    });

    test('a QUOTED configuration name should not let the search cross into '
        'the next block', () {
      // O pbxproj poe entre aspas todo nome com hifen — `name = "Debug-free";`
      // e como o Xcode escreve flavor. Uma regex com `\w+` nao casa ali, e a
      // busca seguia para o bloco seguinte e parava no `name = Release;` DELE:
      // lia as buildSettings do Debug e dizia que eram do Release.
      pbxproj(<({String name, String plist})>[
        (name: '"Debug-staging"', plist: 'Runner/DebugProfile.entitlements'),
        (name: 'Release', plist: 'Runner/Release.entitlements'),
      ]);
      plist('Runner/DebugProfile.entitlements');
      plist('Runner/Release.entitlements');

      final ({String path, String source})? found =
          SignCommand.defaultEntitlements(project.path);

      expect(
        found?.path,
        p.join(project.path, 'macos', 'Runner/Release.entitlements'),
        reason: 'o plist do bloco de Release, nao o do bloco citado antes dele',
      );
    });

    test('a project with flavours should fall back to the template, because '
        'there is no single Release to guess', () {
      pbxproj(<({String name, String plist})>[
        (name: '"Release-free"', plist: 'Runner/Free.entitlements'),
        (name: '"Release-paid"', plist: 'Runner/Paid.entitlements'),
      ]);
      plist('Runner/Free.entitlements');
      plist('Runner/Paid.entitlements');
      plist('Runner/Release.entitlements');

      final ({String path, String source})? found =
          SignCommand.defaultEntitlements(project.path);

      expect(found?.source, contains('template'));
    });

    test('a Release block whose plist is missing should fall back, and say '
        'which source it used', () {
      pbxproj(<({String name, String plist})>[
        (name: 'Release', plist: 'Runner/Gone.entitlements'),
      ]);
      plist('Runner/Release.entitlements');

      final ({String path, String source})? found =
          SignCommand.defaultEntitlements(project.path);

      expect(
        found?.path,
        p.join(project.path, 'macos', 'Runner', 'Release.entitlements'),
      );
      expect(found?.source, contains('template'));
    });

    test(
      'no pbxproj should fall back to the template file, when it exists',
      () {
        plist('Runner/Release.entitlements');

        expect(
          SignCommand.defaultEntitlements(project.path)?.path,
          p.join(project.path, 'macos', 'Runner', 'Release.entitlements'),
        );
      },
    );

    test('nothing to apply should be none, not a guess', () {
      expect(SignCommand.defaultEntitlements(project.path), isNull);
    });
  });

  group('the windows variables the config names', () {
    DovetailConfig windowsConfig(String extra) => DovetailConfig.parse('''
identifier: com.example.demo
name: Demo
manufacturer: Example
targets: [windows-x86_64]
sign:
  windows:
$extra''');

    test('certificate-env, password-env and timestamp-url should feed the '
        'names the signer reads', () {
      final Map<String, String> environment = SignCommand.withWindowsFromConfig(
        <String, String>{'MY_CERT': '/certs/code.pfx', 'MY_PASS': 'secret'},
        windowsConfig(
          '    certificate-env: MY_CERT\n'
          '    password-env: MY_PASS\n'
          '    timestamp-url: http://timestamp.example\n',
        ),
      );

      expect(environment['WINDOWS_CERTIFICATE_FILE'], '/certs/code.pfx');
      expect(environment['WINDOWS_CERTIFICATE_PASSWORD'], 'secret');
      expect(environment['WINDOWS_TIMESTAMP_URL'], 'http://timestamp.example');
    });

    test('an EMPTY WINDOWS_CERTIFICATE_FILE should count as absent', () {
      final Map<String, String> environment = SignCommand.withWindowsFromConfig(
        <String, String>{'WINDOWS_CERTIFICATE_FILE': '', 'MY_CERT': '/x.pfx'},
        windowsConfig('    certificate-env: MY_CERT\n'),
      );

      expect(environment['WINDOWS_CERTIFICATE_FILE'], '/x.pfx');
    });

    test('timestamp-url alone should NOT be injected: it would turn a '
        'credential-less local build into a half-configured refusal', () {
      // Os dois grupos de credenciais contam WINDOWS_TIMESTAMP_URL como
      // membro; com so ele definido, a politica ve um membro presente e os
      // outros ausentes e recusa como "half configured" — depois do build.
      final Map<String, String> environment = SignCommand.withWindowsFromConfig(
        const <String, String>{},
        windowsConfig('    timestamp-url: http://timestamp.example\n'),
      );

      expect(environment, isNot(contains('WINDOWS_TIMESTAMP_URL')));
    });

    test('timestamp-url WITH a certificate should be injected', () {
      final Map<String, String> environment = SignCommand.withWindowsFromConfig(
        <String, String>{'MY_CERT': '/x.pfx'},
        windowsConfig(
          '    certificate-env: MY_CERT\n'
          '    timestamp-url: http://timestamp.example\n',
        ),
      );

      expect(environment['WINDOWS_TIMESTAMP_URL'], 'http://timestamp.example');
    });

    test('the WINDOWS_* names already set should win', () {
      final Map<String, String> environment = SignCommand.withWindowsFromConfig(
        <String, String>{
          'MY_CERT': '/from/config.pfx',
          'WINDOWS_CERTIFICATE_FILE': '/from/env.pfx',
          'WINDOWS_TIMESTAMP_URL': 'http://env.example',
        },
        windowsConfig(
          '    certificate-env: MY_CERT\n'
          '    timestamp-url: http://config.example\n',
        ),
      );

      expect(environment['WINDOWS_CERTIFICATE_FILE'], '/from/env.pfx');
      expect(environment['WINDOWS_TIMESTAMP_URL'], 'http://env.example');
    });

    test('no sign.windows should change nothing', () {
      expect(
        SignCommand.withWindowsFromConfig(<String, String>{'A': 'b'}, null),
        <String, String>{'A': 'b'},
      );
    });
  });

  group('the project wiring, end to end with a recording runner', () {
    late Directory project;

    setUp(() => project = Directory.systemTemp.createTempSync('sign_wire'));
    tearDown(() => project.deleteSync(recursive: true));

    void projectWith(String sign) {
      File(p.join(project.path, 'dovetail.yaml')).writeAsStringSync(
        'identifier: com.example.demo\nname: Demo\nmanufacturer: Example\n'
        'targets: [darwin-aarch64]\n$sign',
      );
      Directory(
        p.join(project.path, 'macos', 'Runner.xcodeproj'),
      ).createSync(recursive: true);
      File(
        p.join(project.path, 'macos', 'Runner.xcodeproj', 'project.pbxproj'),
      ).writeAsStringSync(
        '\t\t0000 /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n'
        '\t\t\tbuildSettings = {\n'
        '\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;\n'
        '\t\t\t};\n\t\t\tname = Release;\n\t\t};\n',
      );
      File(p.join(project.path, 'macos', 'Runner', 'Release.entitlements'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<plist/>');
      Directory(p.join(project.path, 'Example.app')).createSync();
    }

    /// The yaml of a project that embeds a privileged component.
    ///
    /// `route` and `entitlements` are the two the tests below vary, because
    /// they are the two that decide whether anything reaches codesign at all.
    String serviceYaml({required String route, String? entitlements}) =>
        'service:\n'
        '  macos:\n'
        '    label: com.example.demo.helper\n'
        '    program: demo-helper\n'
        '    binary: target/release/demo-helper\n'
        '    route: $route\n'
        '${entitlements == null ? '' : '    entitlements: $entitlements\n'}';

    String helperEntitlementsAt(String relative) {
      final String path = p.join(project.path, relative);
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('<plist><!-- no app-sandbox --></plist>');
      return path;
    }

    Future<_Recording> signBundle({
      List<String> extra = const <String>[],
    }) async {
      final _Recording recording = _Recording();
      final CommandRunner<int> runner = CommandRunner<int>('dovetail', 'test')
        ..addCommand(
          SignCommand(
            runner: recording,
            environment: <String, String>{
              'APPLE_SIGNING_IDENTITY': 'Developer ID Application: X',
            },
            root: project.path,
          ),
        );
      expect(
        await runner.run(<String>[
          'sign',
          '--target',
          'macos',
          '--bundle',
          p.join(project.path, 'Example.app'),
          ...extra,
        ]),
        0,
      );
      return recording;
    }

    /// The codesign call that signed one nested path, or null.
    List<String>? signatureOf(_Recording recording, String relative) {
      final String absolute = p.join(project.path, 'Example.app', relative);
      for (final List<String> call in recording.calls) {
        if (call.first == 'codesign' && call.contains(absolute)) {
          return call;
        }
      }
      return null;
    }

    test('the declared entitlements of an embedded component should reach '
        'codesign for that binary, and not the app\'s', () async {
      projectWith(
        'sign:\n  macos:\n    identity-env: APPLE_SIGNING_IDENTITY\n'
        '${serviceYaml(route: 'bundled', entitlements: 'macos/Helper.entitlements')}',
      );
      final String helper = helperEntitlementsAt('macos/Helper.entitlements');
      Directory(
        p.join(project.path, 'Example.app', 'Contents', 'MacOS'),
      ).createSync(recursive: true);
      File(
        p.join(project.path, 'Example.app', 'Contents', 'MacOS', 'demo-helper'),
      ).writeAsStringSync('binary');

      final List<String>? call = signatureOf(
        await signBundle(),
        p.join('Contents', 'MacOS', 'demo-helper'),
      );

      expect(
        call,
        isNotNull,
        reason:
            'the component lives inside the bundle, so codesign walks it '
            'either way — the question was only ever which entitlements it '
            'would carry',
      );
      expect(
        call,
        containsAllInOrder(<String>['--entitlements', helper]),
        reason:
            'without this the component is signed with whatever the '
            'application got, and an application carries app-sandbox — which '
            'leaves a privileged process unable to reach a socket or a disk '
            'outside its container',
      );
    });

    test('a component installed from outside the bundle should contribute no '
        'entitlements here', () async {
      projectWith(
        'sign:\n  macos:\n    identity-env: APPLE_SIGNING_IDENTITY\n'
        '${serviceYaml(route: 'system', entitlements: 'macos/Helper.entitlements')}',
      );
      helperEntitlementsAt('macos/Helper.entitlements');

      final _Recording recording = await signBundle();

      expect(
        signatureOf(recording, p.join('Contents', 'MacOS', 'demo-helper')),
        isNull,
        reason:
            'on that route the binary is put in place by an installer running '
            'as root, so there is nothing inside this .app to sign for it',
      );
    });

    test('a declared entitlements file that is not on disk should be refused, '
        'naming the path', () async {
      projectWith(
        'sign:\n  macos:\n    identity-env: APPLE_SIGNING_IDENTITY\n'
        '${serviceYaml(route: 'bundled', entitlements: 'macos/Absent.entitlements')}',
      );

      await expectLater(
        signBundle(),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('Absent.entitlements'),
          ),
        ),
        reason:
            'carrying on would sign the component with the application\'s '
            'entitlements, which is the exact outcome the key exists to '
            'prevent — a silent fallback is worse than a refusal',
      );
    });

    test('a flag naming the same path should win over the declaration', () async {
      projectWith(
        'sign:\n  macos:\n    identity-env: APPLE_SIGNING_IDENTITY\n'
        '${serviceYaml(route: 'bundled', entitlements: 'macos/Helper.entitlements')}',
      );
      helperEntitlementsAt('macos/Helper.entitlements');
      final String override = helperEntitlementsAt('macos/Other.entitlements');
      Directory(
        p.join(project.path, 'Example.app', 'Contents', 'MacOS'),
      ).createSync(recursive: true);
      File(
        p.join(project.path, 'Example.app', 'Contents', 'MacOS', 'demo-helper'),
      ).writeAsStringSync('binary');

      final List<String>? call = signatureOf(
        await signBundle(
          extra: <String>[
            '--entitlements-for',
            'Contents/MacOS/demo-helper=$override',
          ],
        ),
        p.join('Contents', 'MacOS', 'demo-helper'),
      );

      expect(
        call,
        containsAllInOrder(<String>['--entitlements', override]),
        reason:
            'the person typing the flag is looking at this signature now, and '
            'the yaml was written months ago',
      );
    });

    test('identity-env and the Release entitlements should both reach '
        'codesign', () async {
      projectWith('sign:\n  macos:\n    identity-env: MY_ID\n');
      final _Recording recording = _Recording();
      final CommandRunner<int> runner = CommandRunner<int>('dovetail', 'test')
        ..addCommand(
          SignCommand(
            runner: recording,
            environment: <String, String>{
              'MY_ID': 'Developer ID Application: X',
            },
            root: project.path,
          ),
        );

      expect(
        await runner.run(<String>[
          'sign',
          '--target',
          'macos',
          '--bundle',
          p.join(project.path, 'Example.app'),
        ]),
        0,
      );

      final List<String> codesign = recording.calls.firstWhere(
        (List<String> call) => call.first == 'codesign',
      );
      expect(
        codesign,
        containsAllInOrder(<String>['--sign', 'Developer ID Application: X']),
        reason: 'a variavel que o yaml nomeia chegou ao codesign',
      );
      expect(
        codesign,
        containsAllInOrder(<String>[
          '--entitlements',
          p.join(project.path, 'macos', 'Runner/Release.entitlements'),
        ]),
        reason: 'sem --entitlements, o plist de Release do projeto e aplicado',
      );
    });

    test('a yaml that does not parse should be a note, and the sign should '
        'still run on APPLE_SIGNING_IDENTITY', () async {
      File(
        p.join(project.path, 'dovetail.yaml'),
      ).writeAsStringSync('identifier: demo\n');
      Directory(p.join(project.path, 'Example.app')).createSync();
      final _Recording recording = _Recording();
      final CommandRunner<int> runner = CommandRunner<int>('dovetail', 'test')
        ..addCommand(
          SignCommand(
            runner: recording,
            environment: <String, String>{'APPLE_SIGNING_IDENTITY': 'X'},
            root: project.path,
          ),
        );

      expect(
        await runner.run(<String>[
          'sign',
          '--target',
          'macos',
          '--bundle',
          p.join(project.path, 'Example.app'),
        ]),
        0,
        reason: 'sign nunca dependeu do yaml; um invalido nao pode derruba-lo',
      );
      expect(
        recording.calls.any((List<String> c) => c.first == 'codesign'),
        true,
      );
    });
  });

  group('the Team ID the bundle and its embedded daemon carry', () {
    late Directory project;

    setUp(() => project = Directory.systemTemp.createTempSync('sign_teamid'));
    tearDown(() => project.deleteSync(recursive: true));

    /// A project whose daemon was embedded, and the recording standing in
    /// for `codesign` while signing and while reading the Team IDs back.
    ///
    /// The two `-dv` reads answer what a real `codesign -dv` would: the app
    /// first, the daemon second, the display on STDERR, `not set` when the
    /// signature is ad-hoc. [daemonOnDisk] false is a daemon that signing
    /// never reached — the second read fails, like it would on disk.
    ({Future<int?> Function() run, _Recording recording}) bundleWithDaemon({
      required String route,
      String appTeamId = 'not set',
      String daemonTeamId = 'not set',
      bool daemonOnDisk = true,
    }) {
      File(p.join(project.path, 'dovetail.yaml')).writeAsStringSync(
        'identifier: com.example.demo\nname: Demo\nmanufacturer: Example\n'
        'targets: [darwin-aarch64]\n'
        'service:\n  macos:\n'
        '    label: com.example.demo.helper\n'
        '    program: demo-helper\n'
        '    binary: target/release/demo-helper\n'
        '    route: $route\n',
      );
      final String app = p.join(project.path, 'Example.app');
      Directory(app).createSync();
      if (daemonOnDisk) {
        Directory(p.join(app, 'Contents', 'MacOS')).createSync(recursive: true);
        File(
          p.join(app, 'Contents', 'MacOS', 'demo-helper'),
        ).writeAsStringSync('binary');
      }
      final _Recording recording = _Recording();
      int teamIdReads = 0;
      recording.onRun = (String executable, List<String> arguments) {
        if (executable != 'codesign' || !arguments.contains('-dv')) {
          return null;
        }
        teamIdReads++;
        final bool readingTheDaemon = teamIdReads == 2;
        return ProcessOutcome(
          exitCode: daemonOnDisk || !readingTheDaemon ? 0 : 1,
          stdout: '',
          stderr:
              'Executable=/x\nIdentifier=com.example.demo.helper\n'
              'TeamIdentifier=${readingTheDaemon ? daemonTeamId : appTeamId}\n',
        );
      };
      Future<int?> run() {
        final CommandRunner<int> runner = CommandRunner<int>('dovetail', 'test')
          ..addCommand(
            SignCommand(
              runner: recording,
              environment: <String, String>{
                'APPLE_SIGNING_IDENTITY': 'Developer ID Application: X',
              },
              root: project.path,
            ),
          );
        return runner.run(<String>[
          'sign',
          '--target',
          'macos',
          '--bundle',
          app,
        ]);
      }

      return (run: run, recording: recording);
    }

    int readsOf(_Recording recording) => recording.calls
        .where((List<String> call) => call.contains('-dv'))
        .length;

    test('a daemon whose Team ID differs from the app\'s should be refused, '
        'naming both values and where the daemon sits', () async {
      final steps = bundleWithDaemon(
        route: 'bundled',
        appTeamId: 'TEAMAAAAAA',
        daemonTeamId: 'TEAMB88888',
      );

      await expectLater(
        steps.run(),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            allOf(
              contains('TEAMAAAAAA'),
              contains('TEAMB88888'),
              contains('demo-helper'),
            ),
          ),
        ),
        reason:
            'o SMAppService recusa o registro na máquina de quem usa, com uma '
            'mensagem sobre a qual ele não pode agir — a recusa tem de '
            'acontecer aqui, onde re-assinar custa um comando',
      );
      expect(
        readsOf(steps.recording),
        2,
        reason: 'o app e o daemon embarcado são os dois lidos, não um',
      );
    });

    test('the refusal should still read the Team ID when a runner hands the '
        'display over on stdout, merged with stderr', () async {
      // `codesign -dv` escreve o display no STDERR. Um runner não é obrigado
      // a manter os dois canais separados — um que junta tudo no stdout é
      // legítimo —, e o parser que olhasse só um deles pararia de ver um
      // Team ID que a máquina real imprime no outro.
      final _Recording recording = _Recording();
      int teamIdReads = 0;
      recording.onRun = (String executable, List<String> arguments) {
        if (executable != 'codesign' || !arguments.contains('-dv')) {
          return null;
        }
        teamIdReads++;
        final String team = teamIdReads == 1 ? 'TEAMAAAAAA' : 'TEAMB88888';
        return ProcessOutcome(
          exitCode: 0,
          stdout: 'Executable=/x\nTeamIdentifier=$team\n',
          stderr: '',
        );
      };
      final String app = p.join(project.path, 'Example.app');
      Directory(p.join(app, 'Contents', 'MacOS')).createSync(recursive: true);
      File(
        p.join(app, 'Contents', 'MacOS', 'demo-helper'),
      ).writeAsStringSync('binary');
      File(p.join(project.path, 'dovetail.yaml')).writeAsStringSync(
        'identifier: com.example.demo\nname: Demo\nmanufacturer: Example\n'
        'targets: [darwin-aarch64]\n'
        'service:\n  macos:\n'
        '    label: com.example.demo.helper\n'
        '    program: demo-helper\n'
        '    binary: target/release/demo-helper\n'
        '    route: bundled\n',
      );
      final CommandRunner<int> runner = CommandRunner<int>('dovetail', 'test')
        ..addCommand(
          SignCommand(
            runner: recording,
            environment: <String, String>{
              'APPLE_SIGNING_IDENTITY': 'Developer ID Application: X',
            },
            root: project.path,
          ),
        );

      await expectLater(
        runner.run(<String>['sign', '--target', 'macos', '--bundle', app]),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            allOf(contains('TEAMAAAAAA'), contains('TEAMB88888')),
          ),
        ),
      );
    });

    test('the system route should run no comparison at all', () async {
      final steps = bundleWithDaemon(
        route: 'system',
        appTeamId: 'TEAMAAAAAA',
        daemonTeamId: 'TEAMB88888',
      );

      expect(await steps.run(), 0);
      expect(
        readsOf(steps.recording),
        0,
        reason:
            'na rota system o binário é posto no lugar por um instalador fora '
            'do .app; não há daemon embarcado cujo Team ID tenha de casar',
      );
    });

    test('no service.macos should run no comparison at all', () async {
      File(p.join(project.path, 'dovetail.yaml')).writeAsStringSync(
        'identifier: com.example.demo\nname: Demo\nmanufacturer: Example\n'
        'targets: [darwin-aarch64]\n',
      );
      Directory(p.join(project.path, 'Example.app')).createSync();
      final _Recording recording = _Recording();
      final CommandRunner<int> runner = CommandRunner<int>('dovetail', 'test')
        ..addCommand(
          SignCommand(
            runner: recording,
            environment: <String, String>{
              'APPLE_SIGNING_IDENTITY': 'Developer ID Application: X',
            },
            root: project.path,
          ),
        );

      expect(
        await runner.run(<String>[
          'sign',
          '--target',
          'macos',
          '--bundle',
          p.join(project.path, 'Example.app'),
        ]),
        0,
      );
      expect(readsOf(recording), 0);
    });

    test('a Team ID reported as not set on both sides should end in 0: '
        'nothing was compared', () async {
      final steps = bundleWithDaemon(route: 'bundled');

      expect(await steps.run(), 0);
      expect(readsOf(steps.recording), 2);
    });

    test('a daemon that signing never reached should be refused before any '
        'Team ID is compared', () async {
      final steps = bundleWithDaemon(route: 'bundled', daemonOnDisk: false);

      await expectLater(
        steps.run(),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.message,
            'message',
            contains('not inside the bundle'),
          ),
        ),
        reason:
            'um daemon ausente produz, na máquina de quem usa, o mesmo '
            'resultado do que a ausência do registro: nada. Aqui a recusa '
            'aponta o caminho que estava vazio',
      );
    });
  });

  group('the identity variable the config names', () {
    DovetailConfig configNaming(String variable) => DovetailConfig.parse('''
identifier: com.example.demo
name: Demo
manufacturer: Example
targets: [darwin-aarch64]
sign:
  macos:
    identity-env: $variable
''');

    test(
      'should feed APPLE_SIGNING_IDENTITY when only the named one is set',
      () {
        // A doc, o init e o doctor falavam de sign.macos.identity-env; o signer
        // so lia APPLE_SIGNING_IDENTITY. Quem exportou a variavel documentada
        // via o build sair sem assinar, sem saber por que.
        final Map<String, String> environment =
            SignCommand.withIdentityFromConfig(<String, String>{
              'DOVETAIL_MACOS_IDENTITY': 'Developer ID X',
            }, configNaming('DOVETAIL_MACOS_IDENTITY'));

        expect(environment['APPLE_SIGNING_IDENTITY'], 'Developer ID X');
      },
    );

    test('an APPLE_SIGNING_IDENTITY already set should win', () {
      final Map<String, String> environment =
          SignCommand.withIdentityFromConfig(<String, String>{
            'DOVETAIL_MACOS_IDENTITY': 'from config',
            'APPLE_SIGNING_IDENTITY': 'from apple',
          }, configNaming('DOVETAIL_MACOS_IDENTITY'));

      expect(environment['APPLE_SIGNING_IDENTITY'], 'from apple');
    });

    test('a whitespace-only APPLE_SIGNING_IDENTITY should count as absent, '
        'like the policy does', () {
      final Map<String, String> environment =
          SignCommand.withIdentityFromConfig(<String, String>{
            'APPLE_SIGNING_IDENTITY': '   ',
            'DOVETAIL_MACOS_IDENTITY': 'from config',
          }, configNaming('DOVETAIL_MACOS_IDENTITY'));

      expect(environment['APPLE_SIGNING_IDENTITY'], 'from config');
    });

    test('an EMPTY APPLE_SIGNING_IDENTITY should count as absent, so the '
        'named variable still wins', () {
      // Um runner de CI materializa um secret que nao existe como string
      // vazia — exatamente o caso em que a variavel documentada tem de valer.
      final Map<String, String> environment =
          SignCommand.withIdentityFromConfig(<String, String>{
            'APPLE_SIGNING_IDENTITY': '',
            'DOVETAIL_MACOS_IDENTITY': 'from config',
          }, configNaming('DOVETAIL_MACOS_IDENTITY'));

      expect(environment['APPLE_SIGNING_IDENTITY'], 'from config');
    });

    test('no config, or a named variable that is empty, should change '
        'nothing', () {
      expect(
        SignCommand.withIdentityFromConfig(<String, String>{'A': 'b'}, null),
        <String, String>{'A': 'b'},
      );
      expect(
        SignCommand.withIdentityFromConfig(<String, String>{
          'DOVETAIL_MACOS_IDENTITY': '',
        }, configNaming('DOVETAIL_MACOS_IDENTITY')),
        isNot(contains('APPLE_SIGNING_IDENTITY')),
      );
    });
  });
  group('the ad-hoc identity of the internal channel', () {
    test('--ad-hoc signs with `-` even with nothing exported', () async {
      final _Recording recording = _Recording();
      final String bundle = p.join(root.path, 'Example.app');
      Directory(bundle).createSync();

      final int? outcome =
          await (CommandRunner<int>('dovetail', 'test')..addCommand(
                SignCommand(
                  runner: recording,
                  environment: const <String, String>{},
                ),
              ))
              .run(<String>[
                'sign',
                '--target',
                'macos',
                '--bundle',
                bundle,
                '--ad-hoc',
              ]);

      expect(
        outcome,
        0,
        reason: 'sem identidade exportada, o ad-hoc e o que faz assinar',
      );
      final List<String> codesign = recording.calls.firstWhere(
        (List<String> call) => call.first == 'codesign',
      );
      expect(codesign, containsAllInOrder(<String>['--sign', '-']));
      // E nao notariza, porque nao ha credencial nenhuma.
      expect(
        recording.calls.any((List<String> call) => call.contains('notarytool')),
        isFalse,
      );
    });

    test('without --ad-hoc the same empty environment skips', () async {
      final _Recording recording = _Recording();
      final String bundle = p.join(root.path, 'Example.app');
      Directory(bundle).createSync();

      expect(
        await (CommandRunner<int>('dovetail', 'test')..addCommand(
              SignCommand(
                runner: recording,
                environment: const <String, String>{},
              ),
            ))
            .run(<String>['sign', '--target', 'macos', '--bundle', bundle]),
        0,
      );
      expect(
        recording.calls.any((List<String> call) => call.first == 'codesign'),
        isFalse,
        reason: 'sem identidade e sem --ad-hoc, o build fica sem assinar',
      );
    });
  });
}

final class _Recording implements ProcessRunner {
  final List<List<String>> calls = <List<String>>[];

  /// A test installing this hook answers specific calls itself — the
  /// `codesign -dv` reads, which report what a real one would — and
  /// returns null for the calls it does not care about.
  ProcessOutcome? Function(String executable, List<String> arguments)? onRun;

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
    Duration? timeout,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    final ProcessOutcome? answered = onRun?.call(executable, arguments);
    if (answered != null) {
      return answered;
    }
    return ProcessOutcome(
      exitCode: 0,
      stdout: arguments.contains('submit')
          ? '{"status":"Accepted","id":"abc"}'
          : '',
      stderr: '',
    );
  }
}
