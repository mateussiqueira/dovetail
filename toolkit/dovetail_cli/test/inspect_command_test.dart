import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/stdout_capture.dart';

/// The first eight bytes of a 64-bit little-endian Mach-O "thin" header: the
/// magic 0xCFFAEDFE, then the cpu type. Handing them to the inspector is how
/// the command's real Mach-O branch is exercised without building the rust
/// slices the bundler normally compiles.
const List<int> _thinArm64 = <int>[
  0xCF,
  0xFA,
  0xED,
  0xFE,
  0x0C,
  0x00,
  0x00,
  0x01,
];

void main() {
  late Directory root;

  setUp(
    () => root = Directory.systemTemp.createTempSync('dovetail_inspect_cmd'),
  );
  tearDown(() => root.deleteSync(recursive: true));

  CommandRunner<int> runner() =>
      CommandRunner<int>('dovetail', 'test')..addCommand(InspectCommand());

  test('no artefact should refuse, asking for at least one', () async {
    await expectLater(
      runner().run(<String>['inspect']),
      throwsA(
        isA<UsageException>().having(
          (UsageException error) => error.message,
          'message',
          contains('at least one artefact'),
        ),
      ),
    );
  });

  test('a path that does not exist should be refused, not described', () async {
    // Este teste afirmava o contrario — que o comando reporta `unknown` e
    // sai 0 —, e a razao escrita era que "the command does not refuse a
    // missing file; it has no existence check". Ter era o problema.
    //
    // A promessa do comando e "o que o arquivo E, nao o que o nome diz", e
    // num arquivo ausente ele dizia exatamente o que o nome diz: com
    // extensao, `inspect /nao/existe/app.dmg` respondia `kind diskImage` e
    // saia 0. Um `dovetail inspect dist/*.dmg && upload` escrito da forma
    // obvia passava quando o bundle nao produziu nada.
    final String ghost = p.join(root.path, 'never-built.dmg');
    await expectLater(
      runner().run(<String>['inspect', ghost]),
      throwsA(
        isA<UsageException>().having(
          (UsageException failure) => failure.message,
          'message',
          contains('no artefact at $ghost'),
        ),
      ),
    );
  });

  test('an existing plain file should say it only read the name', () async {
    final String deb = p.join(root.path, 'client_2.1.0_arm64.deb');
    File(deb).writeAsStringSync('not really a deb');

    final CapturedStdout out = CapturedStdout();
    final int? code = await capturingStdout(
      out,
      () => runner().run(<String>['inspect', deb]),
    );
    expect(code, 0);
    expect(out.text.toString(), contains('debianPackage'));
    expect(
      out.text.toString(),
      contains('only read the name'),
      reason:
          'a passing line must never read as a verified one; it has to say '
          'that only the name was read',
    );
  });

  test('a Mach-O whose name lies about its arch should exit 1', () async {
    // The bytes are arm64, the name says x86_64 — the exact disagreement the
    // command exists to catch before an artefact ships.
    final String lying = p.join(root.path, 'client_2.1.0_x86_64.dylib');
    File(lying).writeAsBytesSync(_thinArm64);

    final CapturedStdout out = CapturedStdout();
    final int? code = await capturingStdout(
      out,
      () => runner().run(<String>['inspect', lying]),
    );
    expect(code, 1);
    expect(out.text.toString(), contains('DISAGREES'));
    expect(
      out.text.toString(),
      contains('worse than one that fails to build'),
      reason: 'the command says why it failed, not just that it did',
    );
  });
}
