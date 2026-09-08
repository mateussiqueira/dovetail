import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/channel_server.dart';

void main() {
  late Directory home;
  late Directory binDir;
  late Directory appRoot;
  late CommandRunner<int> runner;

  setUp(() {
    home = Directory.systemTemp.createTempSync('dt_update_home');
    binDir = Directory.systemTemp.createTempSync('dt_update_bin');
    appRoot = Directory.systemTemp.createTempSync('dt_update_app');
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(
        UpdateCommand(
          sdkLocator: SdkLocator(home: home.path),
          fetcher: HttpArtifactFetcher(client: trustingClient()),
          binDir: binDir.path,
        ),
      );
  });

  tearDown(() {
    home.deleteSync(recursive: true);
    binDir.deleteSync(recursive: true);
    appRoot.deleteSync(recursive: true);
  });

  Future<int?> update(
    HttpServer server, [
    List<String> extra = const <String>[],
  ]) => runner.run(<String>[
    'update',
    '--base-url',
    channelBase(server),
    ...extra,
  ]);

  /// Uma instalação anterior, como o self-install deixaria: binário +
  /// `sdk/<versão>/` com o que um app aponta.
  void seedInstall(String version) {
    final Directory pkg = Directory(
      p.join(home.path, 'sdk', version, 'packages', 'dovetail'),
    )..createSync(recursive: true);
    File(
      p.join(pkg.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: dovetail\nversion: $version\n');
    Directory(p.join(home.path, 'bin')).createSync(recursive: true);
    File(
      p.join(home.path, 'bin', 'dovetail'),
    ).writeAsStringSync('old binary $version\n');
  }

  /// Um app no [appRoot], já apontado para [version].
  void seedApp(String version) {
    File(
      p.join(appRoot.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: demo\nversion: 0.1.0\n');
    File(p.join(appRoot.path, 'pubspec_overrides.yaml')).writeAsStringSync(
      '# Written by dovetail. Do not version.\n'
      'dependency_overrides:\n'
      '  dovetail:\n'
      '    path: ${p.join(home.path, 'sdk', version, 'packages', 'dovetail')}\n',
    );
  }

  String overridesText() =>
      File(p.join(appRoot.path, 'pubspec_overrides.yaml')).readAsStringSync();

  group('update', () {
    test('a newer channel installs the SDK and re-points the app', () async {
      seedInstall(DovetailVersion.number);
      seedApp(DovetailVersion.number);
      final HttpServer server = await serveSdkChannel(
        latest: '0.2.0',
        versions: <String>[DovetailVersion.number, '0.2.0'],
      );
      addTearDown(() => server.close(force: true));

      expect(await update(server, <String>['--root', appRoot.path]), 0);

      expect(
        Directory(
          p.join(home.path, 'sdk', '0.2.0', 'packages', 'dovetail'),
        ).existsSync(),
        true,
      );
      expect(
        overridesText(),
        contains(p.join(home.path, 'sdk', '0.2.0', 'packages', 'dovetail')),
      );
      expect(
        overridesText(),
        isNot(contains(DovetailVersion.number)),
        reason: 'o override antigo sumiu por inteiro, não convive com o novo',
      );
    });

    test('already current is a no-op, nothing changes', () async {
      seedInstall(DovetailVersion.number);
      final HttpServer server = await serveSdkChannel(
        latest: DovetailVersion.number,
        versions: <String>[DovetailVersion.number],
      );
      addTearDown(() => server.close(force: true));

      expect(await update(server), 0);
      expect(
        File(p.join(home.path, 'bin', 'dovetail')).readAsStringSync(),
        'old binary ${DovetailVersion.number}\n',
        reason: 'nada muda quando nada há para atualizar',
      );
    });

    test('without --root updates the SDK and skips the app step', () async {
      seedInstall(DovetailVersion.number);
      final HttpServer server = await serveSdkChannel(
        latest: '0.2.0',
        versions: <String>[DovetailVersion.number, '0.2.0'],
      );
      addTearDown(() => server.close(force: true));

      expect(await update(server), 0);
      expect(
        Directory(
          p.join(home.path, 'sdk', '0.2.0', 'packages', 'dovetail'),
        ).existsSync(),
        true,
      );
      expect(
        File(p.join(appRoot.path, 'pubspec_overrides.yaml')).existsSync(),
        false,
        reason: 'sem --root o app não é tocado',
      );
    });

    test('no SDK at all refuses, naming self-install', () async {
      seedApp(DovetailVersion.number);
      final HttpServer server = await serveSdkChannel(
        latest: DovetailVersion.number,
        versions: <String>[DovetailVersion.number],
      );
      addTearDown(() => server.close(force: true));

      await expectLater(
        update(server, <String>['--root', appRoot.path]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('self-install'),
          ),
        ),
      );
    });
  });
}
