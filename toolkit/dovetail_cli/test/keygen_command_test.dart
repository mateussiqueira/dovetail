import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

bool get _hasMinisign =>
    Process.runSync('which', <String>['minisign']).exitCode == 0;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_keygen');
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: demo_app\nversion: 1.0.0\n');
    File(p.join(root.path, ConfigLocator.fileName)).writeAsStringSync('''
identifier: com.example.demo
name: Demo
manufacturer: Example Ltda
targets: [darwin-aarch64]
update:
  key: keys/update.key
  password-env: DEMO_KEY_PASSWORD
  manifest: dist/latest.json
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  // --root rather than Directory.current: cwd is process-wide, shared by every
  // suite in the run, so a test that parks it in a temp directory makes any
  // other suite that derives a path from it skip in silence.
  Future<int?> keygen(List<String> extra) =>
      (CommandRunner<int>('dovetail', 'test')..addCommand(KeygenCommand())).run(
        <String>['keygen', '--root', root.path, ...extra],
      );

  String at(String relative) => p.join(root.path, relative);

  test('it should write the pair where the config says', () async {
    if (!_hasMinisign) {
      markTestSkipped('minisign is needed to generate anything');
      return;
    }

    expect(await keygen(<String>['--unencrypted']), 0);
    expect(File(at('keys/update.key')).existsSync(), true);
    expect(
      File(at('keys/update.pub')).existsSync(),
      true,
      reason: 'the public half sits beside the secret one, named for it',
    );
  });

  test('the printed public key should be the form the manifest uses', () async {
    if (!_hasMinisign) {
      markTestSkipped('minisign is needed to generate anything');
      return;
    }
    await keygen(<String>['--unencrypted']);

    final String onDisk = File(at('keys/update.pub')).readAsStringSync();
    final String wrapped = base64.encode(utf8.encode(onDisk));

    expect(
      MinisignPublicKey.parse(wrapped).keyIdHex,
      MinisignPublicKey.parse(onDisk).keyIdHex,
      reason:
          'update.public-key and tauri.conf.json both carry base64 around the '
          'minisign text, so what keygen prints has to be that form',
    );
  });

  test('a second run should refuse rather than strand the park', () async {
    if (!_hasMinisign) {
      markTestSkipped('minisign is needed to generate anything');
      return;
    }
    await keygen(<String>['--unencrypted']);
    final String first = File(at('keys/update.key')).readAsStringSync();

    await expectLater(
      keygen(<String>['--unencrypted']),
      throwsA(
        isA<ConfigFailure>().having(
          (ConfigFailure failure) => failure.remedy,
          'remedy',
          contains('only from an installer'),
        ),
      ),
    );
    expect(
      File(at('keys/update.key')).readAsStringSync(),
      first,
      reason: 'the refusal has to leave the existing key untouched',
    );
  });

  test('an unset password variable should refuse, not assume empty', () async {
    await expectLater(
      keygen(<String>[]),
      throwsA(
        isA<ConfigFailure>().having(
          (ConfigFailure failure) => failure.message,
          'message',
          contains('DEMO_KEY_PASSWORD is not set'),
        ),
      ),
      reason:
          'Tauri assumes "" under CI; a key generated that way is protected by '
          'nothing and says so to nobody',
    );
    expect(File(at('keys/update.key')).existsSync(), false);
  });

  test('no config and no --out should say so, not guess a path', () async {
    File(p.join(root.path, ConfigLocator.fileName)).deleteSync();

    await expectLater(
      keygen(<String>['--unencrypted']),
      throwsA(isA<UsageException>()),
    );
  });

  test('--out should win over the config', () async {
    if (!_hasMinisign) {
      markTestSkipped('minisign is needed to generate anything');
      return;
    }

    expect(
      await keygen(<String>['--unencrypted', '--out', 'secrets/park.key']),
      0,
    );
    expect(File(at('secrets/park.key')).existsSync(), true);
    expect(File(at('secrets/park.pub')).existsSync(), true);
    expect(File(at('keys/update.key')).existsSync(), false);
  });
}
