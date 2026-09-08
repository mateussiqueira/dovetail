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
  late CommandRunner<int> runner;

  setUp(() {
    home = Directory.systemTemp.createTempSync('dt_sdk_home');
    binDir = Directory.systemTemp.createTempSync('dt_bin_dir');
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(
        SelfUpdateCommand(
          sdkLocator: SdkLocator(home: home.path),
          fetcher: HttpArtifactFetcher(client: trustingClient()),
          binDir: binDir.path,
        ),
      );
  });

  tearDown(() {
    home.deleteSync(recursive: true);
    binDir.deleteSync(recursive: true);
  });

  Future<int?> update(HttpServer server) =>
      runner.run(<String>['self-update', '--base-url', channelBase(server)]);

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

  group('self-update', () {
    test('the same version as the binary is a no-op', () async {
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

    test('an older latest is nothing to do, not a downgrade', () async {
      seedInstall(DovetailVersion.number);
      final HttpServer server = await serveSdkChannel(
        latest: '0.0.9',
        versions: <String>['0.0.9'],
      );
      addTearDown(() => server.close(force: true));

      expect(await update(server), 0);
      expect(
        Directory(p.join(home.path, 'sdk', '0.0.9')).existsSync(),
        false,
        reason: 'self-update nunca instala por cima de uma versão mais nova',
      );
    });

    test(
      'a newer latest installs beside the old, which keeps working',
      () async {
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
          Directory(
            p.join(
              home.path,
              'sdk',
              DovetailVersion.number,
              'packages',
              'dovetail',
            ),
          ).existsSync(),
          true,
          reason:
              'apps apontados para a versão anterior continuam resolvendo — é '
              'o aceite da fase',
        );
        expect(
          File(p.join(home.path, 'bin', 'dovetail')).readAsStringSync(),
          contains('dovetail 0.2.0'),
          reason: 'o binário é trocado; o symlink nem precisa ser re-apontado',
        );
      },
    );

    test('a channel with no release yet is nothing to do', () async {
      final HttpServer server = await serveSdkChannel(versions: <String>[]);
      addTearDown(() => server.close(force: true));

      expect(await update(server), 0);
      expect(Directory(p.join(home.path, 'sdk')).existsSync(), false);
    });
  });
}
