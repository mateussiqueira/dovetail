import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String bundle;
  late CommandRunner<int> runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_bundlethin');
    bundle = p.join(root.path, 'Example.app');
    final ByteData header = ByteData(72)
      ..setUint32(0, 0xFEEDFACF, Endian.little)
      ..setUint32(4, MachO.cpuTypeArm64, Endian.little);
    File(p.join(bundle, 'Contents', 'MacOS', 'client'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(header.buffer.asUint8List());
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(BundleCommand());
  });

  tearDown(() => root.deleteSync(recursive: true));

  List<String> thinTo(String arch) => <String>[
    'bundle',
    '--target',
    'macos',
    '--macos-format',
    'thin',
    '--product-name',
    'Example',
    '--manufacturer',
    'Example Ltda',
    '--identifier',
    'io.example.client',
    '--version',
    '2.1.0',
    '--main-binary',
    'client',
    '--app-dir',
    bundle,
    '--out-dir',
    p.join(root.path, 'out'),
    '--root',
    root.path,
    '--arch',
    arch,
  ];

  test('thin should keep the bundle in place when it already has the '
      'arch', () async {
    expect(await runner.run(thinTo('arm64')), 0);
    expect(Directory(p.join(root.path, 'out')).existsSync(), false);
  });

  test('thin should refuse an arch the bundle does not carry', () async {
    await expectLater(
      runner.run(thinTo('x86_64')),
      throwsA(
        isA<BundleFailure>().having(
          (BundleFailure failure) => failure.message,
          'message',
          contains('cannot be thinned to x86_64'),
        ),
      ),
    );
  });
}
