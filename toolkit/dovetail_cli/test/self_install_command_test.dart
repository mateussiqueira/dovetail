import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:dovetail_cli/src/sdk/sdk_channel.dart';
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
        SelfInstallCommand(
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

  Future<int?> install(HttpServer server) =>
      runner.run(<String>['self-install', '--base-url', channelBase(server)]);

  group('self-install', () {
    test('should put the runtime beside the binary and link it', () async {
      final HttpServer server = await serveSdkChannel(
        latest: DovetailVersion.number,
        versions: <String>[DovetailVersion.number],
      );
      addTearDown(() => server.close(force: true));

      expect(await install(server), 0);

      const String version = DovetailVersion.number;
      expect(File(p.join(home.path, 'bin', 'dovetail')).existsSync(), true);
      expect(
        File(
          p.join(
            home.path,
            'sdk',
            version,
            'packages',
            'dovetail',
            'pubspec.yaml',
          ),
        ).existsSync(),
        true,
      );

      final Link link = Link(p.join(binDir.path, 'dovetail'));
      expect(link.existsSync(), true);
      expect(
        link.targetSync(),
        p.join(home.path, 'bin', 'dovetail'),
        reason:
            'o symlink aponta para o binário instalado, para o PATH ver '
            'a troca de versão sem re-symlink',
      );
    });

    test('should refuse without a channel, naming flag and env', () async {
      await expectLater(
        runner.run(<String>['self-install']),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.toString(),
            'toString()',
            contains(SdkChannel.installUrlEnv),
          ),
        ),
      );
      expect(Directory(p.join(home.path, 'sdk')).existsSync(), false);
    });

    test('should refuse a tarball that fails its published sha256', () async {
      final HttpServer server = await serveSdkChannel(
        latest: DovetailVersion.number,
        versions: <String>[DovetailVersion.number],
        corruptShaFor: <String>{DovetailVersion.number},
      );
      addTearDown(() => server.close(force: true));

      await expectLater(install(server), throwsA(isA<UpdateFailure>()));
      expect(
        Directory(
          p.join(home.path, 'sdk', DovetailVersion.number),
        ).existsSync(),
        false,
        reason: 'um tarball cujo hash não bate nunca é desempacotado',
      );
    });

    test(
      'a version the channel does not publish is refused, not half-done',
      () async {
        final HttpServer server = await serveSdkChannel(
          latest: DovetailVersion.number,
          versions: <String>['0.0.9'],
        );
        addTearDown(() => server.close(force: true));

        await expectLater(install(server), throwsA(isA<UpdateFailure>()));
        expect(
          Directory(
            p.join(home.path, 'sdk', DovetailVersion.number),
          ).existsSync(),
          false,
        );
      },
    );
  });
}
