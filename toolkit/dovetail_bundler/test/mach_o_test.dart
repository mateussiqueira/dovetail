import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

final String _realApp = inRepo(<String>[
  'product',
  'vpn_desktop',
  'build',
  'macos',
  'Build',
  'Products',
  'Debug',
  'vpn_desktop.app',
]);

final String _shortcutRust = inRepo(<String>[
  'toolkit',
  'dovetail_shortcut_channel',
  'rust',
]);

String _slice(TargetArch arch) => p.join(
  _shortcutRust,
  'target',
  arch.rustTriple(TargetOs.macos),
  'release',
  'libdesktop_shortcut_channel.dylib',
);

Set<TargetArch> _lipoSays(String path) =>
    Process.runSync('lipo', <String>['-archs', path]).stdout
        .toString()
        .trim()
        .split(RegExp(r'\s+'))
        .where((String name) => name.isNotEmpty)
        .map(TargetArch.parse)
        .toSet();

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_macho'));
  tearDown(() => root.deleteSync(recursive: true));

  group('MachO.parse', () {
    Uint8List header(List<int> bytes) =>
        Uint8List.fromList(<int>[...bytes, ...List<int>.filled(64, 0)]);

    test('should read a little-endian 64-bit thin arm64 header', () {
      final MachOInfo info = MachO.parse(
        header(<int>[0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01]),
      );
      expect(info.kind, MachOKind.thin);
      expect(info.architectures, <TargetArch>{TargetArch.arm64});
    });

    test('should read a little-endian 64-bit thin x86_64 header', () {
      final MachOInfo info = MachO.parse(
        header(<int>[0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01]),
      );
      expect(info.architectures, <TargetArch>{TargetArch.x86_64});
    });

    test('should read a fat header carrying both architectures', () {
      final MachOInfo info = MachO.parse(
        header(<int>[
          0xCA,
          0xFE,
          0xBA,
          0xBE,
          0x00,
          0x00,
          0x00,
          0x02,
          0x01,
          0x00,
          0x00,
          0x07,
          0,
          0,
          0,
          3,
          0,
          0,
          0x40,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          14,
          0x01,
          0x00,
          0x00,
          0x0C,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          14,
        ]),
      );
      expect(info.kind, MachOKind.fat);
      expect(info.architectures, <TargetArch>{
        TargetArch.x86_64,
        TargetArch.arm64,
      });
      expect(info.isUniversal, true);
    });

    test('should record a cpu type it does not know rather than drop it', () {
      final MachOInfo info = MachO.parse(
        header(<int>[0xCF, 0xFA, 0xED, 0xFE, 0x12, 0x00, 0x00, 0x00]),
      );
      expect(info.isMachO, true);
      expect(info.architectures, isEmpty);
      expect(info.unknownCpuTypes, <int>{0x12});
    });

    test('a shell script should not read as Mach-O', () {
      expect(
        MachO.parse(
          Uint8List.fromList('#!/bin/sh\necho hi\n'.codeUnits),
        ).isMachO,
        false,
      );
    });

    test('a png should not read as Mach-O', () {
      expect(
        MachO.parse(
          Uint8List.fromList(<int>[
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A,
          ]),
        ).isMachO,
        false,
      );
    });

    test('a file shorter than a magic should not read as Mach-O', () {
      expect(MachO.parse(Uint8List.fromList(<int>[0xCF, 0xFA])).isMachO, false);
    });

    test('reading a path that does not exist should not throw', () {
      expect(MachO.read(p.join(root.path, 'absent')).isMachO, false);
    });
  });

  group('MachO against lipo, on real binaries', () {
    test('should agree with lipo on each cross-compiled slice', () {
      for (final TargetArch arch in TargetArch.values) {
        final String path = _slice(arch);
        if (!File(path).existsSync()) {
          markTestSkipped('build both apple slices first');
          return;
        }
        expect(MachO.read(path).architectures, _lipoSays(path), reason: path);
      }
    });

    test('should agree with lipo on a merged universal library', () async {
      if (!TargetArch.values.every(
        (TargetArch a) => File(_slice(a)).existsSync(),
      )) {
        markTestSkipped('build both apple slices first');
        return;
      }
      final String fat =
          await const UniversalBinary(runner: SystemProcessRunner()).merge(
            slices: <TargetArch, String>{
              for (final TargetArch arch in TargetArch.values)
                arch: _slice(arch),
            },
            output: p.join(root.path, 'fat.dylib'),
          );

      expect(MachO.read(fat).kind, MachOKind.fat);
      expect(MachO.read(fat).architectures, _lipoSays(fat));
      expect(MachO.read(fat).architectures, hasLength(2));
    });

    test('should agree with lipo on every Mach-O inside the real app', () {
      if (!Directory(_realApp).existsSync()) {
        markTestSkipped('build vpn_desktop for macOS first');
        return;
      }

      final BundleArchitectureReport report = BundleArchitectures.inspect(
        bundlePath: _realApp,
      );
      expect(report.binaries, isNotEmpty);

      for (final BundleBinary binary in report.binaries) {
        expect(
          binary.info.architectures,
          _lipoSays(p.join(_realApp, binary.relativePath)),
          reason: binary.relativePath,
        );
      }
    });
  });

  group('BundleArchitectures', () {
    test('the real arm-only app should be refused as universal', () {
      if (!Directory(_realApp).existsSync()) {
        markTestSkipped('build vpn_desktop for macOS first');
        return;
      }

      expect(
        () => BundleArchitectures.enforce(
          bundlePath: _realApp,
          required_: <TargetArch>{TargetArch.x86_64, TargetArch.arm64},
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.message,
            'message',
            contains('do not carry'),
          ),
        ),
      );
    });

    test('the real app should satisfy the architecture it was built for', () {
      if (!Directory(_realApp).existsSync()) {
        markTestSkipped('build vpn_desktop for macOS first');
        return;
      }

      final BundleArchitectureReport report = BundleArchitectures.inspect(
        bundlePath: _realApp,
        required_: <TargetArch>{TargetArch.arm64},
      );
      expect(report.satisfied, true, reason: report.summary);
      expect(report.carriedByAll, <TargetArch>{TargetArch.arm64});
    });

    test(
      'the summary should name the files that are short, not just count',
      () {
        if (!Directory(_realApp).existsSync()) {
          markTestSkipped('build vpn_desktop for macOS first');
          return;
        }

        final String summary = BundleArchitectures.inspect(
          bundlePath: _realApp,
          required_: <TargetArch>{TargetArch.x86_64, TargetArch.arm64},
        ).summary;

        expect(summary, contains('Contents/MacOS/vpn_desktop'));
        expect(summary, contains('arm64'));
      },
    );

    test('a bundle with no Mach-O at all should not count as satisfied', () {
      final Directory empty = Directory(p.join(root.path, 'Empty.app'))
        ..createSync(recursive: true);
      File(p.join(empty.path, 'readme.txt')).writeAsStringSync('nothing');

      final BundleArchitectureReport report = BundleArchitectures.inspect(
        bundlePath: empty.path,
        required_: <TargetArch>{TargetArch.arm64},
      );
      expect(report.satisfied, false);
      expect(report.summary, contains('no Mach-O file'));
    });

    test('should refuse a bundle path that does not exist', () {
      expect(
        () => BundleArchitectures.inspect(
          bundlePath: p.join(root.path, 'Absent.app'),
        ),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('DmgBundler with an architecture promise', () {
    BundleSpec specFor(String app) => BundleSpec(
      productName: 'Example',
      manufacturer: 'Example Ltda',
      identifier: 'io.example.client',
      version: AppVersion.parse('2.1.0'),
      mainBinaryName: 'client',
      appDirectory: app,
      outputDirectory: p.join(root.path, 'out'),
    );

    test('the file name should say which architectures it carries', () {
      final BundleSpec spec = specFor(_realApp);
      expect(
        const DmgBundler(runner: SystemProcessRunner()).fileNameFor(spec),
        'client_2.1.0.dmg',
      );
      expect(
        const DmgBundler(
          runner: SystemProcessRunner(),
          requiredArchitectures: <TargetArch>{TargetArch.arm64},
        ).fileNameFor(spec),
        'client_2.1.0_arm64.dmg',
      );
      expect(
        const DmgBundler(
          runner: SystemProcessRunner(),
          requiredArchitectures: <TargetArch>{
            TargetArch.x86_64,
            TargetArch.arm64,
          },
        ).fileNameFor(spec),
        'client_2.1.0_universal.dmg',
      );
    });

    test('should refuse to wrap a thin app in a universal dmg', () async {
      if (!Directory(_realApp).existsSync()) {
        markTestSkipped('build vpn_desktop for macOS first');
        return;
      }

      await expectLater(
        const DmgBundler(
          runner: SystemProcessRunner(),
          requiredArchitectures: <TargetArch>{
            TargetArch.x86_64,
            TargetArch.arm64,
          },
        ).bundle(specFor(_realApp)),
        throwsA(isA<BundleFailure>()),
        reason:
            'hdiutil would have wrapped it happily; the refusal has to come '
            'before the tool runs',
      );
      expect(Directory(p.join(root.path, 'out')).existsSync(), false);
    });
  });
}
