// O primeiro teste que sobe o CLI paga o compile do kernel (~1-9s, frio, num
// SSD externo) dentro do proprio timeout, e nao mais num setUpAll: margem
// para nao virar vermelho intermitente num runner frio.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:dovetail_cli/src/doctor/binary_report.dart';
import 'package:dovetail_cli/src/sdk/sdk_overrides.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/cli_kernel.dart';

void main() {
  late Directory root;

  // O CLI compilado uma vez, e nao a cada `doctor(...)`.
  //
  // `dart run bin/dovetail.dart` recompila tudo do zero por invocacao — ~1,58s
  // medidos — e esta suite o invoca dezoito vezes. Eram ~28s dos ~30s dela, no
  // pacote que domina o alvo `test`.
  CliKernel.install();

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_doctor'));

  tearDown(() => root.deleteSync(recursive: true));

  void configure(String targets) {
    File(p.join(root.path, ConfigLocator.fileName)).writeAsStringSync(
      'identifier: com.example.demo\nname: Demo\nmanufacturer: Example Ltda\ntargets: [$targets]\n',
    );
  }

  ProcessResult doctor(List<String> extra) =>
      CliKernel.run(<String>['doctor', ...extra], workingDirectory: root.path);

  group('the target key the config speaks', () {
    test('a platform key should map to the bundler name and arch', () {
      final TargetKey key = TargetKey.parse('darwin-aarch64');

      expect(key.os, 'macos', reason: 'darwin on the wire, macos on disk');
      expect(key.arch, TargetArch.arm64);
      expect(key.platformKey, 'darwin-aarch64');
    });

    test('x86_64 should be the one target Intel and AMD share', () {
      expect(TargetKey.parse('linux-x86_64').arch, TargetArch.x86_64);
      expect(TargetKey.parse('windows-x86_64').arch, TargetArch.x86_64);
    });

    test('an arch the bundler cannot build for should probe without one', () {
      expect(TargetKey.parse('linux-riscv64').arch, isNull);
      expect(TargetKey.parse('linux-riscv64').os, 'linux');
    });
  });

  group('which targets it walks', () {
    test(
      'with a config it should report every declared target',
      () {
        configure('darwin-aarch64, darwin-x86_64');

        final String out = doctor(<String>[]).stdout as String;

        expect(out, contains('target: darwin-aarch64'));
        expect(out, contains('target: darwin-x86_64'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'an explicit --target should win over the config',
      () {
        configure('linux-x86_64');

        final String out =
            doctor(<String>['--target', 'macos']).stdout as String;

        expect(out, contains('target: macos'));
        expect(out, isNot(contains('linux-x86_64')));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'an explicit target should still name its architecture',
      () {
        final String out =
            doctor(<String>['--target', 'windows', '--arch', 'arm64']).stdout
                as String;

        expect(
          out,
          contains('target: windows/arm64'),
          reason:
              'the header is the only place the reader learns which pair was '
              'probed, and dropping the arch makes two runs look identical',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'with no config anywhere it should probe the host',
      () {
        final String out = doctor(<String>[]).stdout as String;

        expect(out, contains('target: '));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('the sdk section', () {
    late Directory sdkHome;

    setUp(() {
      sdkHome = Directory.systemTemp.createTempSync('dovetail_sdk_home');
    });

    tearDown(() => sdkHome.deleteSync(recursive: true));

    void installSdk(String version) {
      final Directory pkg = Directory(
        p.join(sdkHome.path, 'sdk', version, 'packages', 'dovetail'),
      )..createSync(recursive: true);
      File(
        p.join(pkg.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: dovetail\nversion: $version\n');
    }

    ProcessResult doctorWithSdk(List<String> extra) => CliKernel.run(
      <String>['doctor', ...extra],
      workingDirectory: root.path,
      environment: <String, String>{'DOVETAIL_HOME': sdkHome.path},
    );

    test(
      'an installed SDK should come back ok with its version',
      () {
        installSdk(DovetailVersion.number);

        final String out = doctorWithSdk(<String>[]).stdout as String;

        expect(out, contains('sdk'));
        expect(out, contains('ok       version'));
        expect(out, contains(DovetailVersion.number));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'no SDK should be off — never missing — naming both install paths',
      () {
        final String out = doctorWithSdk(<String>[]).stdout as String;

        expect(out, contains('sdk'));
        expect(
          out,
          contains('off      install'),
          reason:
              'o SDK é opcional dentro do monorepo: off, não missing, para o '
              'doctor de projeto não bloquear um dev que resolve por path',
        );
        expect(out, contains('install.sh'));
        expect(out, contains('self-install'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a version ahead of the binary should name the tool that catches up',
      () {
        installSdk('0.2.0');

        final String out = doctorWithSdk(<String>[]).stdout as String;

        expect(out, contains('0.2.0'));
        expect(
          out,
          contains('self-update'),
          reason:
              'a seção sdk que diz a discordância sem nomear a saída '
              'manda o leitor procurar o comando no README',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a version older than the binary should name the tool that installs it',
      () {
        installSdk('0.0.1');

        final String out = doctorWithSdk(<String>[]).stdout as String;

        expect(out, contains('0.0.1'));
        expect(
          out,
          contains('self-install'),
          reason:
              'a seção sdk que diz a discordância sem nomear a saída '
              'manda o leitor procurar o comando no README',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('the binary section', () {
    late Directory fakeBin;

    setUp(() {
      fakeBin = Directory.systemTemp.createTempSync('dovetail_fake_bin');
    });

    tearDown(() => fakeBin.deleteSync(recursive: true));

    // Um `dovetail` de mentira no PATH: responde --version e --help como o
    // CommandRunner responderia, com o commit e os comandos que o teste
    // manda. A sonda nao sabe que e um shell script, e nao deve saber.
    void plantFake({required String commit, required List<String> commands}) {
      final StringBuffer help = StringBuffer()
        ..writeln('The dovetail desktop toolkit.')
        ..writeln()
        ..writeln('Usage: dovetail <command> [arguments]')
        ..writeln()
        ..writeln('Available commands:');
      for (final String command in commands) {
        help.writeln('  $command   does $command');
      }
      help
        ..writeln()
        ..writeln('Run "dovetail help <command>" for more information.');

      final File script = File(p.join(fakeBin.path, 'dovetail'))
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'case "\$1" in\n'
          '  --version) echo "dovetail 0.1.0 (macos-arm64, dart 3.12.2, commit $commit)" ;;\n'
          '  --help) cat <<"HELP"\n'
          '${help.toString()}'
          'HELP\n'
          '  ;;\n'
          '  *) exit 64 ;;\n'
          'esac\n',
        );
      Process.runSync('chmod', <String>['+x', script.path]);
    }

    ProcessResult doctorWithPath() => CliKernel.run(
      <String>['doctor'],
      workingDirectory: root.path,
      environment: <String, String>{
        'PATH': '${fakeBin.path}:${Platform.environment['PATH'] ?? ''}',
      },
    );

    test(
      'a PATH binary missing commands the tree has should be off and name them',
      () {
        plantFake(
          commit: 'abc1234',
          commands: <String>['build', 'doctor', 'help', 'init'],
        );

        final String out = doctorWithPath().stdout as String;

        expect(out, contains('binary'));
        expect(out, contains('off      path'));
        expect(out, contains(p.join(fakeBin.path, 'dovetail')));
        expect(out, contains('abc1234'));
        expect(
          out,
          contains('probe'),
          reason:
              'o comando que vai faltar tem de estar escrito, nao so contado',
        );
        expect(out, contains('build_release.sh --install'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a PATH binary that knows every command should be ok',
      () {
        // O conjunto que ESTE processo registra, lido do proprio CLI para o
        // teste nao envelhecer quando um comando entrar.
        final String help =
            CliKernel.run(<String>[
                  '--help',
                ], workingDirectory: root.path).stdout
                as String;
        final List<String> everyCommand = BinaryReport.commandsOf(help).toList()
          ..sort();
        expect(everyCommand, isNotEmpty);

        plantFake(commit: 'abc1234', commands: everyCommand);

        final String out = doctorWithPath().stdout as String;

        expect(out, contains('binary'));
        expect(out, contains('ok       path'));
        expect(out, contains('abc1234'));
        expect(out, isNot(contains('fewer command')));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'no dovetail on PATH should be off, never a crash',
      () {
        final ProcessResult ran = CliKernel.run(
          <String>['doctor'],
          workingDirectory: root.path,
          environment: <String, String>{'PATH': fakeBin.path},
        );

        final String out = ran.stdout as String;
        expect(out, contains('binary'));
        expect(out, contains('off      path'));
        expect(out, contains('no dovetail on PATH'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('the app section', () {
    late Directory sdkHome;

    setUp(() {
      sdkHome = Directory.systemTemp.createTempSync('dovetail_app_home');
    });

    tearDown(() => sdkHome.deleteSync(recursive: true));

    void installSdk(String version) {
      final Directory pkg = Directory(
        p.join(sdkHome.path, 'sdk', version, 'packages', 'dovetail'),
      )..createSync(recursive: true);
      File(
        p.join(pkg.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: dovetail\nversion: $version\n');
    }

    void writeOverrides(String version) {
      File(p.join(root.path, SdkOverrides.fileName)).writeAsStringSync(
        'dependency_overrides:\n'
        '  dovetail:\n'
        '    path: ${p.join(sdkHome.path, 'sdk', version, 'packages', 'dovetail')}\n',
      );
    }

    ProcessResult doctorWithSdk(List<String> extra) => CliKernel.run(
      <String>['doctor', ...extra],
      workingDirectory: root.path,
      environment: <String, String>{'DOVETAIL_HOME': sdkHome.path},
    );

    test(
      'no pubspec_overrides.yaml should be off, naming init --sdk',
      () {
        final String out = doctorWithSdk(<String>[]).stdout as String;

        expect(out, contains('app'));
        expect(out, contains('off      overrides'));
        expect(
          out,
          contains('init --sdk'),
          reason:
              'sem override o app ainda resolve por path, então é off e não '
              'missing — e a nota tem que apontar o comando que escreve o '
              'arquivo',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'overrides at an installed version should be ok with the version',
      () {
        installSdk('0.1.0');
        writeOverrides('0.1.0');

        final String out = doctorWithSdk(<String>[]).stdout as String;

        expect(out, contains('app'));
        expect(out, contains('ok       overrides'));
        expect(out, contains('0.1.0'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'overrides at a missing version should be off, naming upgrade',
      () {
        installSdk('0.1.0');
        writeOverrides('0.9.9');

        final String out = doctorWithSdk(<String>[]).stdout as String;

        expect(out, contains('app'));
        expect(out, contains('off      overrides'));
        expect(out, contains('0.9.9'));
        expect(
          out,
          contains('upgrade'),
          reason:
              'a seção app que aponta uma versão sem nomear o comando que a '
              'alcança manda o leitor procurar no README',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('the spm section', () {
    late Directory sdkHome;

    setUp(() {
      sdkHome = Directory.systemTemp.createTempSync('dovetail_spm_home');
    });

    tearDown(() => sdkHome.deleteSync(recursive: true));

    void installSdkPlugin(String version) {
      final Directory pkg = Directory(
        p.join(
          sdkHome.path,
          'sdk',
          version,
          'packages',
          'dovetail_shortcut_channel',
        ),
      )..createSync(recursive: true);
      File(p.join(pkg.path, 'pubspec.yaml')).writeAsStringSync(
        'name: dovetail_shortcut_channel\nversion: $version\n',
      );
      final Directory macos = Directory(
        p.join(pkg.path, 'macos', 'dovetail_shortcut_channel'),
      )..createSync(recursive: true);
      File(
        p.join(macos.path, 'Package.swift'),
      ).writeAsStringSync('// swift-tools-version: 5.9\n');
    }

    void writeXcframework(String version) {
      Directory(
        p.join(
          sdkHome.path,
          'sdk',
          version,
          'packages',
          'dovetail_shortcut_channel',
          'macos',
          'dovetail_shortcut_channel',
          'dovetail_shortcut_channel.xcframework',
        ),
      ).createSync(recursive: true);
    }

    ProcessResult doctorWithSdk(List<String> extra) => CliKernel.run(
      <String>['doctor', ...extra],
      workingDirectory: root.path,
      environment: <String, String>{'DOVETAIL_HOME': sdkHome.path},
    );

    test(
      'a Package.swift with no .xcframework should be off, naming the script',
      () {
        installSdkPlugin('0.1.0');

        final String out = doctorWithSdk(<String>[]).stdout as String;

        expect(out, contains('spm'));
        expect(out, contains('off      dovetail_shortcut_channel'));
        expect(
          out,
          contains('build_xcframework.sh'),
          reason:
              'o .xcframework não é versionado; quem mudou Rust e esqueceu de '
              'reconstruir só descobre no build — o doctor tem que nomear o '
              'script que fecha a distância',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a plugin with its .xcframework built should be ok with the version',
      () {
        installSdkPlugin('0.1.0');
        writeXcframework('0.1.0');

        final String out = doctorWithSdk(<String>[]).stdout as String;

        expect(out, contains('spm'));
        expect(out, contains('ok       dovetail_shortcut_channel'));
        expect(out, contains('0.1.0'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'no SDK at all should be off, naming self-install',
      () {
        final String out = doctorWithSdk(<String>[]).stdout as String;

        expect(out, contains('spm'));
        expect(out, contains('off      install'));
        expect(out, contains('self-install'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('--check-updates', () {
    test('no SDK installed should name the channel latest', () {
      expect(
        DoctorCommand.verdict(installed: null, latest: '0.2.0'),
        'no SDK installed; latest is 0.2.0',
      );
    });

    test('an installed version equal to latest should be up to date', () {
      expect(
        DoctorCommand.verdict(installed: '0.1.0', latest: '0.1.0'),
        'up to date (0.1.0)',
      );
    });

    test('an older install should name the self-update path', () {
      expect(
        DoctorCommand.verdict(installed: '0.9.0', latest: '0.10.0'),
        'update available: 0.9.0 → 0.10.0 (dovetail self-update)',
        reason:
            'a string compare would call 0.9.0 newer than 0.10.0; the verdict '
            'has to order by numeric segment',
      );
    });

    test('an install ahead of the channel should say so', () {
      expect(
        DoctorCommand.verdict(installed: '0.3.0', latest: '0.2.0'),
        'installed 0.3.0 is ahead of channel latest 0.2.0',
      );
    });

    test('a channel with no release should not crash the verdict', () {
      expect(
        DoctorCommand.verdict(installed: '0.1.0', latest: null),
        contains('no release yet'),
      );
      expect(
        DoctorCommand.verdict(installed: null, latest: null),
        contains('no release yet'),
      );
    });

    test(
      'a dead channel should print an off note and not crash the doctor',
      () {
        final ProcessResult result = CliKernel.run(
          <String>['doctor', '--check-updates'],
          workingDirectory: root.path,
          environment: <String, String>{
            'DOVETAIL_INSTALL_URL': 'https://127.0.0.1:1',
          },
        );

        final String out = result.stdout as String;

        expect(out, contains('updates'));
        expect(out, contains('off      check'));
        expect(
          <int>[0, 1, 2],
          contains(result.exitCode),
          reason:
              'the network failure is a note, not a crash — the exit code '
              'stays the doctor outcome, never an uncaught-exception code',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
