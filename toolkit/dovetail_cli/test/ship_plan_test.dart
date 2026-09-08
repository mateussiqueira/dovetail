import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

DovetailConfig configWith(String targets, {String extra = ''}) =>
    DovetailConfig.parse('''
identifier: com.example.demo
name: Demo Client
manufacturer: Example Ltda
targets: [$targets]
$extra
''');

ShipPlan planFor(
  String targets, {
  String host = 'macos',
  String extra = '',
  bool build = true,
  String? windowsFormat = 'msi',
  Map<String, String>? environment,
}) => ShipPlan.of(
  config: configWith(targets, extra: extra),
  version: '4.2.0',
  host: host,
  binary: 'demo_app',
  build: build,
  windowsFormat: windowsFormat,
  environment: environment,
);

const String _notarising = 'sign:\n  macos:\n    notarize: true\n';
const Map<String, String> _releaseEnvironment = <String, String>{
  'APPLE_SIGNING_IDENTITY': 'Developer ID Application: Example',
  'APPLE_ID': 'someone@example.com',
  'APPLE_PASSWORD': 'app-specific',
  'APPLE_TEAM_ID': 'TEAM123',
};

List<String> labelsOf(ShipPlan plan) =>
    plan.steps.map((ShipStep step) => step.label).toList();

List<String> argumentsOf(ShipPlan plan, String label) =>
    plan.steps.firstWhere((ShipStep step) => step.label == label).arguments;

void main() {
  group('which steps a host gets', () {
    test('windows should sign the payload before the installer wraps it', () {
      expect(
        labelsOf(planFor('windows-x86_64', host: 'windows')),
        <String>[
          'build windows',
          'sign payload windows-x86_64',
          'bundle windows-x86_64',
          'sign windows-x86_64',
        ],
        reason:
            'um instalador assinado cujos binarios internos nao foram '
            'assinados passa pelo SmartScreen e entao deposita executaveis sem '
            'assinatura no disco de quem instalou — pior que nao assinar, '
            'porque parece certo',
      );
    });

    test(
      'the payload step should point at the build output, not the installer',
      () {
        expect(
          argumentsOf(
            planFor('windows-x86_64', host: 'windows'),
            'sign payload windows-x86_64',
          ),
          <String>[
            '--target',
            'windows',
            '--directory',
            'build/windows/x64/runner/Release',
          ],
        );
      },
    );

    test('the installer step should still name one file, not a directory', () {
      final List<String> arguments = argumentsOf(
        planFor('windows-x86_64', host: 'windows'),
        'sign windows-x86_64',
      );
      expect(arguments, contains('--file'));
      expect(
        arguments,
        isNot(contains('--directory')),
        reason:
            'varrer o diretorio de saida depois de empacotar reassinaria os '
            'binarios que ja foram assinados, e o instalador nem mora la',
      );
    });

    test('linux should get one signing step, and macos two', () {
      // O Linux nao assina binario nenhum: o que sai de la e um SHA256SUMS,
      // um passo so.
      expect(
        labelsOf(
          planFor('linux-x86_64', host: 'linux'),
        ).where((String label) => label.startsWith('sign')),
        hasLength(1),
      );
      // O macOS sao DOIS, e este teste ja afirmou o contrario. O selo do
      // `.app` cobre o conteudo — isso sempre esteve certo —, mas o `.dmg` e
      // ele proprio um artefato que o Gatekeeper avalia quando o usuario monta
      // a imagem. Com um passo so, o arquivo que a pessoa BAIXA saia sem
      // assinatura mesmo com um Developer ID configurado.
      expect(
        labelsOf(
          planFor('darwin-aarch64'),
        ).where((String label) => label.startsWith('sign')),
        hasLength(2),
      );
    });

    test('macos should sign the app, wrap it, sign the dmg, then archive the '
        'app for the updater', () {
      expect(
        labelsOf(planFor('darwin-aarch64, darwin-x86_64')),
        <String>[
          'build macos',
          'sign darwin-universal',
          'bundle darwin-universal',
          'sign dmg darwin-universal',
          'archive darwin-universal',
        ],
        reason:
            'assinar o .app depois de o dmg embrulhar nao assina o conteudo, e '
            'assinar so o .app deixa sem assinatura o arquivo que o usuario '
            'baixa — sao os dois, nesta ordem',
      );
    });

    test('a single macos arch should not claim to be universal', () {
      expect(labelsOf(planFor('darwin-aarch64')), <String>[
        'build macos',
        'sign darwin-aarch64',
        'bundle darwin-aarch64',
        'sign dmg darwin-aarch64',
        'archive darwin-aarch64',
      ]);
    });

    test('the archive step should ask bundle for the tar, with the same '
        'identity fields', () {
      final List<String> arguments = argumentsOf(
        planFor('darwin-aarch64'),
        'archive darwin-aarch64',
      );

      expect(arguments, containsAllInOrder(<String>['--macos-format', 'tar']));
      expect(
        arguments,
        containsAllInOrder(<String>[
          '--app-dir',
          'build/macos/Build/Products/Release/demo_app.app',
        ]),
        reason: 'o mesmo .app assinado que o dmg embrulhou',
      );
    });

    test('windows and linux sign the installer, so bundle comes first', () {
      expect(labelsOf(planFor('linux-x86_64', host: 'linux')), <String>[
        'build linux',
        'bundle linux-x86_64',
        'sign linux-x86_64',
      ]);
    });

    test('linux should get one bundle per architecture', () {
      expect(
        labelsOf(planFor('linux-x86_64, linux-aarch64', host: 'linux')),
        <String>[
          'build linux',
          'bundle linux-x86_64',
          'sign linux-x86_64',
          'bundle linux-aarch64',
          'sign linux-aarch64',
        ],
        reason:
            'a .deb carries one architecture; only a macOS bundle can hold two',
      );
    });

    test('targets for another host should be left alone', () {
      expect(
        labelsOf(planFor('darwin-aarch64, windows-x86_64, linux-x86_64')),
        <String>[
          'build macos',
          'sign darwin-aarch64',
          'bundle darwin-aarch64',
          'sign dmg darwin-aarch64',
          'archive darwin-aarch64',
        ],
      );
    });

    test('a host with nothing to build should refuse, and say why', () {
      expect(
        () => planFor('windows-x86_64', host: 'macos'),
        throwsA(
          isA<ConfigFailure>().having(
            (ConfigFailure failure) => failure.remedy,
            'remedy',
            contains('lives elsewhere'),
          ),
        ),
      );
    });

    test('skipping the build should drop only that step', () {
      expect(labelsOf(planFor('darwin-aarch64', build: false)), <String>[
        'sign darwin-aarch64',
        'bundle darwin-aarch64',
        'sign dmg darwin-aarch64',
        'archive darwin-aarch64',
      ]);
    });
  });

  group('the arguments it hands each command', () {
    test('the wire architecture should become the bundler spelling', () {
      expect(
        argumentsOf(planFor('darwin-aarch64'), 'bundle darwin-aarch64'),
        containsAllInOrder(<String>['--arch', 'arm64']),
        reason:
            'the platform key says aarch64 and the bundler option allows only '
            'x86_64 and arm64, so passing the wire spelling is rejected by '
            'the argument parser before any code sees it',
      );
    });

    test('two arches should reach one bundle call twice', () {
      final List<String> arguments = argumentsOf(
        planFor('darwin-aarch64, darwin-x86_64'),
        'bundle darwin-universal',
      );

      expect(arguments.where((String a) => a == '--arch').length, 2);
      expect(arguments, containsAll(<String>['arm64', 'x86_64']));
    });

    test('the identity fields should come from the config', () {
      final List<String> arguments = argumentsOf(
        planFor('darwin-aarch64'),
        'bundle darwin-aarch64',
      );

      expect(
        arguments,
        containsAllInOrder(<String>['--product-name', 'Demo Client']),
      );
      expect(
        arguments,
        containsAllInOrder(<String>['--manufacturer', 'Example Ltda']),
      );
      expect(
        arguments,
        containsAllInOrder(<String>['--identifier', 'com.example.demo']),
      );
      expect(arguments, containsAllInOrder(<String>['--version', '4.2.0']));
    });

    test('the macos app directory should be the bundle, not the folder', () {
      expect(
        argumentsOf(planFor('darwin-aarch64'), 'bundle darwin-aarch64'),
        containsAllInOrder(<String>[
          '--app-dir',
          'build/macos/Build/Products/Release/demo_app.app',
        ]),
        reason:
            'a dmg wraps the bundle, and the bundler refuses the directory '
            'above it',
      );
    });

    test('linux should get the directory, because there is no bundle', () {
      expect(
        argumentsOf(
          planFor('linux-x86_64', host: 'linux'),
          'bundle linux-x86_64',
        ),
        containsAllInOrder(<String>[
          '--app-dir',
          'build/linux/x64/release/bundle',
        ]),
      );
    });

    test('macos should be signed as a bundle, linux as files', () {
      expect(
        argumentsOf(planFor('darwin-aarch64'), 'sign darwin-aarch64'),
        containsAllInOrder(<String>[
          '--bundle',
          'build/macos/Build/Products/Release/demo_app.app',
        ]),
        reason: 'the .app that was built, not one in the output directory',
      );
      expect(
        argumentsOf(
          planFor('linux-x86_64', host: 'linux'),
          'sign linux-x86_64',
        ),
        containsAllInOrder(<String>['--out-dir', 'dist']),
      );
    });

    test('notarisation should be asked for only when configured, and on both '
        'the app and the dmg', () {
      final ShipPlan silent = planFor('darwin-aarch64');
      expect(
        argumentsOf(silent, 'sign darwin-aarch64'),
        isNot(contains('--notarize')),
      );
      expect(
        argumentsOf(silent, 'sign dmg darwin-aarch64'),
        isNot(contains('--notarize')),
      );

      // O .app primeiro, para o ticket ficar grampeado nele — quem arrasta o
      // app da imagem para /Applications abre um app com ticket, offline. O
      // dmg depois, porque e o que se baixa e o Gatekeeper avalia ao montar.
      final ShipPlan notarising = planFor('darwin-aarch64', extra: _notarising);
      expect(
        argumentsOf(notarising, 'sign darwin-aarch64'),
        contains('--notarize'),
      );
      expect(
        argumentsOf(notarising, 'sign dmg darwin-aarch64'),
        contains('--notarize'),
      );
    });

    test('notarize: true should require the signature on both macos steps; '
        'a declared section alone should not', () {
      // `init` escreve sign.macos em TODO projeto, com notarize false: gatear
      // em "secao declarada" faria toda esteira local sem Developer ID morrer
      // depois do build, contra o que a doc promete. Quem declara notarize
      // true declara release de verdade — e ai ficar sem assinar e erro.
      final ShipPlan notarising = planFor('darwin-aarch64', extra: _notarising);
      expect(
        argumentsOf(notarising, 'sign darwin-aarch64'),
        contains('--require-signature'),
      );
      expect(
        argumentsOf(notarising, 'sign dmg darwin-aarch64'),
        contains('--require-signature'),
      );

      final ShipPlan declared = planFor(
        'darwin-aarch64',
        extra: 'sign:\n  macos:\n    identity-env: DOVETAIL_MACOS_IDENTITY\n',
      );
      expect(
        argumentsOf(declared, 'sign darwin-aarch64'),
        isNot(contains('--require-signature')),
      );
      expect(
        argumentsOf(declared, 'sign dmg darwin-aarch64'),
        isNot(contains('--require-signature')),
      );
    });

    test('notarize: true with nothing exported should be refused before the '
        'build, naming both gaps', () {
      final ShipPlan plan = planFor(
        'darwin-aarch64',
        extra: _notarising,
        environment: const <String, String>{},
      );

      expect(plan.refusals, hasLength(2));
      expect(plan.refusals.first, contains('APPLE_SIGNING_IDENTITY'));
      expect(plan.refusals.first, contains('DOVETAIL_MACOS_IDENTITY'));
      expect(plan.refusals.last, contains('APPLE_ID'));
      expect(plan.refusals.last, contains('APPLE_API_KEY_ID'));
    });

    test('the dmg step should sign a --file, never a --bundle', () {
      final List<String> arguments = argumentsOf(
        planFor('darwin-aarch64'),
        'sign dmg darwin-aarch64',
      );

      expect(
        arguments,
        containsAllInOrder(<String>['--file', 'dist/demo_app_4.2.0_arm64.dmg']),
      );
      expect(arguments, isNot(contains('--bundle')));
    });

    test('a whitespace-only identity should be refused like an absent one', () {
      final ShipPlan plan = planFor(
        'darwin-aarch64',
        extra: _notarising,
        environment: <String, String>{
          ..._releaseEnvironment,
          'APPLE_SIGNING_IDENTITY': '   ',
        },
      );

      expect(plan.refusals, hasLength(1));
      expect(plan.refusals.single, contains('APPLE_SIGNING_IDENTITY'));
    });

    test('notarize: true with everything exported should refuse nothing', () {
      expect(
        planFor(
          'darwin-aarch64',
          extra: _notarising,
          environment: _releaseEnvironment,
        ).refusals,
        isEmpty,
      );
    });

    test('the identity may arrive under the variable the config names', () {
      expect(
        planFor(
          'darwin-aarch64',
          extra: _notarising,
          environment: <String, String>{
            ..._releaseEnvironment,
            'APPLE_SIGNING_IDENTITY': '',
            'DOVETAIL_MACOS_IDENTITY': 'Developer ID Application: Example',
          },
        ).refusals,
        isEmpty,
        reason: 'vazia e ausente; a variavel documentada vale',
      );
    });

    test('a half-configured notarisation set should be refused as such', () {
      final ShipPlan plan = planFor(
        'darwin-aarch64',
        extra: _notarising,
        environment: const <String, String>{
          'APPLE_SIGNING_IDENTITY': 'Developer ID Application: Example',
          'APPLE_ID': 'someone@example.com',
        },
      );

      expect(plan.refusals, hasLength(1));
      expect(plan.refusals.single, contains('half configured'));
    });

    test('without an environment the plan stays pure and refuses nothing '
        'about credentials', () {
      expect(planFor('darwin-aarch64', extra: _notarising).refusals, isEmpty);
    });

    test('declared entitlements should reach the app step, not the dmg', () {
      final ShipPlan plan = planFor(
        'darwin-aarch64',
        extra:
            'sign:\n  macos:\n'
            '    entitlements: macos/Runner/Release.entitlements\n',
      );

      expect(
        argumentsOf(plan, 'sign darwin-aarch64'),
        containsAllInOrder(<String>[
          '--entitlements',
          'macos/Runner/Release.entitlements',
        ]),
        reason:
            'codesign --force sem --entitlements apaga os que o build tinha; '
            'o ship nao passava nada',
      );
      expect(
        argumentsOf(plan, 'sign dmg darwin-aarch64'),
        isNot(contains('--entitlements')),
        reason: 'entitlements sao do codigo, nao da imagem',
      );
    });

    test('an msi should carry an upgrade code derived from the identifier', () {
      // O bundle recusa msi sem UpgradeCode, e o ship nunca o passava: um ship
      // Windows morria no passo de bundle, depois do build.
      final List<String> arguments = argumentsOf(
        planFor('windows-x86_64', host: 'windows'),
        'bundle windows-x86_64',
      );

      expect(
        arguments,
        containsAllInOrder(<String>[
          '--upgrade-code',
          UpgradeCode.forIdentifier('com.example.demo'),
        ]),
      );
      expect(
        argumentsOf(
          planFor('windows-x86_64', host: 'windows', windowsFormat: 'nsis'),
          'bundle windows-x86_64',
        ),
        isNot(contains('--upgrade-code')),
        reason: 'o nsis nao tem UpgradeCode; a flag e do msi',
      );
    });

    test('the windows format should reach the bundle call', () {
      expect(
        argumentsOf(
          planFor('windows-x86_64', host: 'windows'),
          'bundle windows-x86_64',
        ),
        containsAllInOrder(<String>['--windows-format', 'msi']),
      );
    });
  });

  group('the artefacts it expects and publishes', () {
    test('the macos manifest artefact should be the app archive, and the dmg '
        'a download', () {
      // O updater extrai tar.gz com um .app dentro; nao monta dmg. Publicar o
      // dmg no manifesto fazia a primeira atualizacao morrer em "could not
      // extract the update archive" depois de baixar e verificar 33 MB.
      final ShipPlan plan = planFor(
        'darwin-aarch64, darwin-x86_64',
        extra:
            'update:\n  key: keys/update.key\n'
            '  base-url: https://cdn.example.com/releases\n',
      );

      expect(plan.artifacts, <String, String>{
        'darwin-universal': 'dist/demo_app_4.2.0_universal.app.tar.gz',
      });
      expect(plan.downloads, <String, String>{
        'darwin-universal': 'dist/demo_app_4.2.0_universal.dmg',
      });
      expect(
        argumentsOf(plan, 'release 4.2.0'),
        containsAllInOrder(<String>[
          '--artifact',
          'darwin-universal=dist/demo_app_4.2.0_universal.app.tar.gz',
        ]),
      );
    });

    test('the debian architecture spelling should be used for the deb', () {
      expect(
        planFor('linux-x86_64', host: 'linux').artifacts['linux-x86_64'],
        'dist/demo_app_4.2.0_amd64.deb',
      );
      expect(
        planFor('linux-aarch64', host: 'linux').artifacts['linux-aarch64'],
        'dist/demo_app_4.2.0_arm64.deb',
      );
    });

    test('the wix spelling should be used for the msi', () {
      expect(
        planFor('windows-x86_64', host: 'windows').artifacts['windows-x86_64'],
        'dist/demo_app_4.2.0_x64.msi',
      );
    });

    test('nsis should be named as a setup exe', () {
      expect(
        planFor(
          'windows-x86_64',
          host: 'windows',
          windowsFormat: 'nsis',
        ).artifacts['windows-x86_64'],
        'dist/demo_app_4.2.0_x64_setup.exe',
      );
    });

    test('an unencrypted key should be passed on, not left to the caller', () {
      expect(
        argumentsOf(
          planFor(
            'darwin-aarch64',
            extra:
                'update:\n  key: keys/update.key\n  unencrypted: true\n  base-url: https://cdn.example.com/releases\n',
          ),
          'release 4.2.0',
        ),
        contains('--unencrypted-key'),
        reason:
            'release refuses to assume an empty password, and ship had no way '
            'to say the key has none',
      );
    });

    test('a key with a password should not claim to have none', () {
      expect(
        argumentsOf(
          planFor(
            'darwin-aarch64',
            extra:
                'update:\n  key: keys/update.key\n  base-url: https://cdn.example.com/releases\n',
          ),
          'release 4.2.0',
        ),
        isNot(contains('--unencrypted-key')),
      );
    });

    test('no update section should mean no release step', () {
      expect(
        labelsOf(planFor('darwin-aarch64')),
        isNot(contains('release 4.2.0')),
      );
    });

    test('an update section should add exactly one release step', () {
      expect(
        labelsOf(
          planFor(
            'linux-x86_64, linux-aarch64',
            host: 'linux',
            extra:
                'update:\n  key: keys/update.key\n  base-url: https://cdn.example.com/releases\n',
          ),
        ).where((String label) => label.startsWith('release')),
        hasLength(1),
        reason: 'one manifest names every artefact, not one manifest each',
      );
    });
  });

  group('the names it predicts must be the names the bundlers write', () {
    test('the dmg suffix should follow the architecture count', () {
      expect(
        planFor('darwin-aarch64').downloads['darwin-aarch64'],
        'dist/demo_app_4.2.0_arm64.dmg',
      );
      expect(
        planFor('darwin-aarch64, darwin-x86_64').downloads['darwin-universal'],
        'dist/demo_app_4.2.0_universal.dmg',
        reason:
            'the plan used to guess this name and the bundler wrote another, '
            'so the manifest pointed at a file that did not exist',
      );
      expect(
        planFor('darwin-aarch64').artifacts['darwin-aarch64'],
        'dist/demo_app_4.2.0_arm64.app.tar.gz',
        reason: 'o manifesto aponta para o que o updater instala',
      );
    });

    test(
      'the updater archive should be named by the bundler that writes it',
      () {
        expect(
          ShipPlan.artifactNameFor(
            host: 'macos',
            binary: 'demo_app',
            version: '4.2.0',
            arches: <String>['arm64', 'x86_64'],
            windowsFormat: null,
            identifier: 'com.example.demo',
            name: 'Demo',
            manufacturer: 'M',
            macosFormat: 'tar',
          ),
          'demo_app_4.2.0_universal.app.tar.gz',
        );
      },
    );

    test('every name should come from the bundler that writes it', () {
      expect(
        ShipPlan.artifactNameFor(
          host: 'linux',
          binary: 'demo_app',
          version: '4.2.0',
          arches: <String>['x86_64'],
          windowsFormat: null,
          identifier: 'com.example.demo',
          name: 'Demo',
          manufacturer: 'M',
        ),
        'demo_app_4.2.0_amd64.deb',
      );
      expect(
        ShipPlan.artifactNameFor(
          host: 'windows',
          binary: 'demo_app',
          version: '4.2.0',
          arches: <String>['arm64'],
          windowsFormat: 'msi',
          identifier: 'com.example.demo',
          name: 'Demo',
          manufacturer: 'M',
        ),
        'demo_app_4.2.0_arm64.msi',
      );
    });
  });

  group('what it refuses before it spends the build', () {
    test('an update section without a base-url should be refused', () {
      expect(
        () => planFor(
          'darwin-aarch64',
          extra: 'update:\n  key: keys/update.key\n',
        ),
        throwsA(
          isA<ConfigFailure>()
              .having(
                (ConfigFailure failure) => failure.message,
                'message',
                contains('update.base-url is not set'),
              )
              .having(
                (ConfigFailure failure) => failure.remedy,
                'remedy',
                contains('base-url: https://your.cdn/releases'),
              ),
        ),
        reason:
            'dovetail init writes base-url commented out, so this is the '
            'default config; ship used to plan every step, build for minutes '
            'and only then have release refuse the two-part --artifact form',
      );
    });

    test('no update section at all should plan no release step', () {
      expect(
        labelsOf(planFor('darwin-aarch64')),
        isNot(contains('release 4.2.0')),
        reason:
            'a project that does not ship updates is not a project with a '
            'broken base-url',
      );
    });
  });

  group('a step is data, so it can be printed before it runs', () {
    test('the invocation should be the command and its arguments', () {
      const ShipStep step = ShipStep(
        label: 'build macos',
        command: 'build',
        arguments: <String>['--target', 'macos'],
      );

      expect(step.invocation, <String>['build', '--target', 'macos']);
      expect(step.toString(), 'build --target macos');
    });
  });
}
