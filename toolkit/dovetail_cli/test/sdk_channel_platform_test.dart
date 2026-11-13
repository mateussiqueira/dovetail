import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

void main() {
  final String cli = p.join(repoRoot(), 'toolkit', 'dovetail_cli');
  late Directory root;
  late File driver;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('dovetail_channel_platform');
    driver = File(p.join(root.path, 'probe.dart'))
      ..writeAsStringSync('''
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dovetail_cli/src/sdk/sdk_channel.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
final class FixtureFetcher implements ArtifactFetcher {
  FixtureFetcher(this.name);
  final String name;
  final List<String> requests = [];
  @override
  Future<FetchedBody> fetch(Uri url, {DownloadProgress? onProgress}) async {
    requests.add(url.path);
    final payload = utf8.encode('verified fixture');
    if (url.path == '/0.2.0/\$name') {
      return FetchedBody(statusCode: 200, bytes: Uint8List.fromList(payload));
    }
    if (url.path == '/0.2.0/\$name.sha256') {
      return FetchedBody(statusCode: 200, bytes: Uint8List.fromList(utf8.encode(sha256.convert(payload).toString())));
    }
    return FetchedBody(statusCode: 404, bytes: Uint8List(0));
  }
}
Future<void> main(List<String> args) async {
  final fetcher = FixtureFetcher(args[0]);
  final channel = SdkChannel(baseUrl: 'https://release.example/', fetcher: fetcher);
  final target = File(args[1]);
  await channel.download('0.2.0', target);
  print(jsonEncode({'name': SdkChannel.tarballName('0.2.0'), 'archive': channel.tarballUrl('0.2.0').path,
    'checksum': channel.shaUrl('0.2.0').path, 'signature': channel.sigUrl('0.2.0').path,
    'requests': fetcher.requests, 'payload': target.readAsStringSync()}));
}
''');
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  for (final String os in <String>['windows', 'macos', 'linux']) {
    for (final String arch in <String>['x64', 'arm64']) {
      test('SDK channel downloads the $os $arch release archive', () {
        final String extension = os == 'windows' ? 'zip' : 'tar.gz';
        final String name = 'dovetail-sdk-0.2.0-$os-$arch.$extension';
        final ProcessResult result =
            Process.runSync(Platform.resolvedExecutable, <String>[
              '--define=dovetail.os=$os',
              '--define=dovetail.arch=$arch',
              '--packages=${p.join(cli, '.dart_tool', 'package_config.json')}',
              driver.path,
              name,
              p.join(root.path, '$os-$arch.download'),
            ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final Map<String, dynamic> value =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        expect(value['name'], name);
        expect(value['archive'], '/0.2.0/$name');
        expect(value['checksum'], '/0.2.0/$name.sha256');
        expect(value['signature'], '/0.2.0/$name.minisig');
        expect(value['requests'], <String>[
          '/0.2.0/$name',
          '/0.2.0/$name.sha256',
        ]);
        expect(value['payload'], 'verified fixture');
      });
    }
  }
}
