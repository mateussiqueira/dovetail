import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/stdout_capture.dart';

final String _entryPoint = p.join(
  Directory.current.path,
  'bin',
  'dovetail.dart',
);

void main() {
  late Directory template;
  late Directory core;
  late Directory out;
  late Directory sdkHome;
  late Directory from;
  late CommandRunner<int> runner;

  setUp(() {
    template = Directory.systemTemp.createTempSync('dt_bridge_tpl');
    core = Directory.systemTemp.createTempSync('dt_bridge_core');
    out = Directory.systemTemp.createTempSync('dt_bridge_out');
    sdkHome = Directory.systemTemp.createTempSync('dt_bridge_sdk');
    from = Directory.systemTemp.createTempSync('dt_bridge_from');
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(BridgeCommand(sdkLocator: SdkLocator(home: sdkHome.path)));
  });

  tearDown(() {
    for (final Directory dir in <Directory>[
      template,
      core,
      out,
      sdkHome,
      from,
    ]) {
      dir.deleteSync(recursive: true);
    }
  });

  void writeTemplate() {
    File(p.join(template.path, 'pubspec.yaml')).writeAsStringSync(
      'name: {{name}}\ncore: {{core_crate_name}}\ndart: {{rust_core_dart_path}}\n',
    );
    Directory(p.join(template.path, 'lib')).createSync(recursive: true);
    File(
      p.join(template.path, 'lib', '{{name}}.dart'),
    ).writeAsStringSync('class {{camel_name}} {}\n');
    File(p.join(template.path, 'rust', 'Cargo.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '[dependencies]\n{{core_crate_name}} = { path = "{{core_path}}" }\n'
        'dovetail_rust_core = { path = "{{rust_core_rust_path}}" }\n',
      );
  }

  void writeCore() {
    File(p.join(core.path, 'Cargo.toml')).writeAsStringSync(
      '[package]\nname = "example-core"\nversion = "1.0.0"\n',
    );
  }

  void writeFrom() {
    File(p.join(from.path, 'rust', 'Cargo.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '[dependencies]\n'
        'example-core = { path = "../../../../example-rust/crates/core" }\n'
        'foo = { path = "../../../../example-rust/crates/foo" }\n'
        'bar = { path = "../../../../example-rust/crates/bar" }\n'
        'dovetail_rust_core = { path = "../../../toolkit/dovetail_rust_core/rust" }\n'
        'flutter_rust_bridge = "=2.13.0"\n',
      );
    File(p.join(from.path, 'rust', 'src', 'api', 'x.rs'))
      ..createSync(recursive: true)
      ..writeAsStringSync('// product repasse\n');
    File(p.join(from.path, 'rust', 'src', 'support.rs'))
      ..createSync(recursive: true)
      ..writeAsStringSync('// typed support\n');
  }

  Future<int?> init(List<String> extra) => runner.run(<String>[
    'bridge',
    'init',
    '--core',
    core.path,
    '--name',
    'probe_bridge',
    '--template',
    template.path,
    '--out',
    out.path,
    ...extra,
  ]);

  group('what it generates', () {
    test('should render every placeholder into the right file', () async {
      writeTemplate();
      writeCore();

      expect(await init(<String>[]), 0);

      expect(
        File(p.join(out.path, 'pubspec.yaml')).readAsStringSync(),
        contains('name: probe_bridge'),
      );
      expect(
        File(p.join(out.path, 'rust', 'Cargo.toml')).readAsStringSync(),
        contains(
          'example-core = { path = "${core.resolveSymbolicLinksSync()}" }',
        ),
      );
      expect(
        File(p.join(out.path, 'lib', 'probe_bridge.dart')).readAsStringSync(),
        contains('class ProbeBridge'),
        reason: 'o nome do arquivo e o da classe vêm do mesmo --name',
      );
    });

    test('the scaffold should not leave a placeholder behind', () async {
      writeTemplate();
      writeCore();

      await init(<String>[]);

      for (final FileSystemEntity entity in Directory(
        out.path,
      ).listSync(recursive: true)) {
        if (entity is File) {
          expect(
            entity.readAsStringSync(),
            isNot(contains('{{')),
            reason: '${entity.path} ainda carrega um placeholder',
          );
        }
      }
    });

    test('a core without src/handle.rs is warned about, not refused', () async {
      writeTemplate();
      writeCore(); // no src/handle.rs

      final CapturedStdout captured = CapturedStdout();
      final int? code = await capturingStdout(captured, () => init(<String>[]));

      expect(code, 0);
      expect(
        captured.text.toString(),
        contains('src/handle.rs not found'),
        reason: 'the discovery should not be deferred to core_coverage_test',
      );
      expect(
        File(p.join(out.path, 'pubspec.yaml')).existsSync(),
        isTrue,
        reason: 'the warning is non-fatal; the scaffold still writes',
      );
    });
  });

  group('what --from copies', () {
    test('--from copies api/, support.rs and the sibling-crate deps', () async {
      writeTemplate();
      writeCore();
      writeFrom();

      expect(await init(<String>['--from', from.path]), 0);

      expect(
        File(p.join(out.path, 'rust', 'src', 'api', 'x.rs')).readAsStringSync(),
        contains('product repasse'),
      );
      expect(
        File(p.join(out.path, 'rust', 'src', 'support.rs')).readAsStringSync(),
        contains('typed support'),
        reason: 'o support.rs tipado do produto substitui o genérico',
      );

      final String cargo = File(
        p.join(out.path, 'rust', 'Cargo.toml'),
      ).readAsStringSync();
      expect(cargo, contains('foo = { path ='));
      expect(cargo, contains('bar = { path ='));
      expect(
        cargo,
        isNot(contains('../../../../example-rust/crates/core')),
        reason: 'o dep do core não é copiado — o template já o declara',
      );
      expect(
        cargo,
        isNot(contains('../../../toolkit/dovetail_rust_core/rust')),
        reason:
            'o dep do dovetail_rust_core não é copiado — o template já o declara',
      );
    });

    test('a --from that does not exist is refused', () async {
      writeTemplate();
      writeCore();

      await expectLater(
        init(<String>['--from', p.join(from.path, 'nowhere')]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('no existing bridge'),
          ),
        ),
      );
    });

    test('a --from without a rust/Cargo.toml is refused', () async {
      writeTemplate();
      writeCore();

      await expectLater(
        init(<String>['--from', from.path]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('rust/Cargo.toml'),
          ),
        ),
      );
    });
  });

  group('what it refuses', () {
    test('--core is not optional', () async {
      writeTemplate();

      await expectLater(
        runner.run(<String>['bridge', 'init', '--name', 'x']),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('--core'),
          ),
        ),
      );
    });

    test('--name is not optional', () async {
      writeCore();

      await expectLater(
        runner.run(<String>['bridge', 'init', '--core', core.path]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('--name'),
          ),
        ),
      );
    });

    test('a name that is not a package name is refused', () async {
      writeCore();

      await expectLater(
        runner.run(<String>[
          'bridge',
          'init',
          '--core',
          core.path,
          '--name',
          '9lives',
        ]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('package name'),
          ),
        ),
      );
    });

    test('a core directory that does not exist is refused', () async {
      await expectLater(
        runner.run(<String>[
          'bridge',
          'init',
          '--core',
          p.join(core.path, 'nowhere'),
          '--name',
          'x',
        ]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('crate'),
          ),
        ),
      );
    });

    test('a core without a Cargo.toml name is refused', () async {
      File(p.join(core.path, 'Cargo.toml')).writeAsStringSync('');

      await expectLater(
        runner.run(<String>[
          'bridge',
          'init',
          '--core',
          core.path,
          '--name',
          'x',
        ]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('name'),
          ),
        ),
      );
    });

    test(
      'a destination that is not empty is refused, not overwritten',
      () async {
        writeTemplate();
        writeCore();
        File(p.join(out.path, 'keep')).writeAsStringSync('do not touch\n');

        await expectLater(
          init(<String>[]),
          throwsA(
            isA<UsageException>().having(
              (UsageException error) => error.message,
              'message',
              contains('already'),
            ),
          ),
        );
        expect(
          File(p.join(out.path, 'keep')).readAsStringSync(),
          'do not touch\n',
        );
      },
    );

    test(
      'without a template anywhere it refuses, naming the installer',
      () async {
        writeCore();
        final Directory empty = Directory.systemTemp.createTempSync('dt_empty');
        addTearDown(() => empty.deleteSync(recursive: true));
        final ProcessResult ran = Process.runSync('dart', <String>[
          'run',
          _entryPoint,
          'bridge',
          'init',
          '--core',
          core.path,
          '--name',
          'x',
        ], workingDirectory: empty.path);

        expect(ran.exitCode, isNot(0));
        expect(ran.stderr.toString(), contains('no bridge template'));
      },
    );
  });
}
