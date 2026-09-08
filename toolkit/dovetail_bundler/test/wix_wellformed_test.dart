import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _upgradeCode = '3F2504E0-4F89-11D3-9A0C-0305E82C3301';

bool get _hasXmllint =>
    Process.runSync('which', <String>['xmllint']).exitCode == 0;

void _write(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

void main() {
  late Directory root;
  late String stage;
  late String out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('wix_xml');
    stage = p.join(root.path, 'stage');
    out = p.join(root.path, 'out');
    _write(p.join(stage, 'client.exe'), 'binary');
    _write(p.join(stage, 'wintun.dll'), 'driver');
    _write(p.join(stage, 'data', 'flutter_assets', 'A & B<x>.bin'), 'asset');
    _write(p.join(stage, 'data', "it's here", 'quote.dat'), 'q');
  });

  tearDown(() => root.deleteSync(recursive: true));

  MsiSpec specWith({
    String productName = 'Example Client',
    String manufacturer = 'Example Ltda',
    TargetArch arch = TargetArch.x86_64,
    InstallMode mode = InstallMode.perMachine,
    List<MsiPrivilegedStep> steps = const <MsiPrivilegedStep>[],
  }) => MsiSpec(
    bundle: BundleSpec(
      productName: productName,
      manufacturer: manufacturer,
      identifier: 'io.example.client',
      version: AppVersion.parse('2.1.0'),
      mainBinaryName: 'client',
      appDirectory: stage,
      outputDirectory: out,
      installMode: mode,
    ),
    upgradeCode: _upgradeCode,
    arch: arch,
    steps: steps,
  );

  String sourceFor(MsiSpec spec) => WixSource.render(
    spec,
    MsiComponentTree.scan(
      appDirectory: spec.bundle.appDirectory,
      upgradeCode: spec.upgradeCode,
    ),
  );

  ProcessResult lint(String xml) {
    final File file = File(p.join(root.path, 'source.wxs'))
      ..writeAsStringSync(xml);
    return Process.runSync('xmllint', <String>['--noout', file.path]);
  }

  group('the .wxs it generates should be well-formed XML', () {
    test('a plain product should parse', () {
      if (!_hasXmllint) {
        markTestSkipped('xmllint is needed to parse it');
        return;
      }

      final ProcessResult parsed = lint(sourceFor(specWith()));

      expect(
        parsed.exitCode,
        0,
        reason:
            'the README claimed this was checked and nothing checked it; a '
            'malformed .wxs fails inside wix build on a machine that is not '
            'this one, with the generator far out of sight\n${parsed.stderr}',
      );
    });

    test('names carrying XML metacharacters should still parse', () {
      if (!_hasXmllint) {
        markTestSkipped('xmllint is needed to parse it');
        return;
      }

      final ProcessResult parsed = lint(
        sourceFor(
          specWith(
            productName: 'Ex & Co <Client>',
            manufacturer: 'M & M "Ltda"',
          ),
        ),
      );

      expect(parsed.exitCode, 0, reason: parsed.stderr.toString());
    });

    test('both architectures should parse', () {
      if (!_hasXmllint) {
        markTestSkipped('xmllint is needed to parse it');
        return;
      }

      for (final TargetArch arch in <TargetArch>[
        TargetArch.x86_64,
        TargetArch.arm64,
      ]) {
        final ProcessResult parsed = lint(sourceFor(specWith(arch: arch)));
        expect(parsed.exitCode, 0, reason: '$arch\n${parsed.stderr}');
      }
    });

    test('a current-user install should parse', () {
      if (!_hasXmllint) {
        markTestSkipped('xmllint is needed to parse it');
        return;
      }

      final ProcessResult parsed = lint(
        sourceFor(specWith(mode: InstallMode.currentUser)),
      );

      expect(parsed.exitCode, 0, reason: parsed.stderr.toString());
    });

    test('the check should be able to fail', () {
      if (!_hasXmllint) {
        markTestSkipped('xmllint is needed to parse it');
        return;
      }

      expect(
        lint('<Wix><Package></Wix>').exitCode,
        isNot(0),
        reason:
            'a parser that accepts anything proves nothing about the four '
            'documents above',
      );
    });
  });
}
