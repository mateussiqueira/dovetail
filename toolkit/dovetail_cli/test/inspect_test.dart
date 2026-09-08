import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

final String _rust = inRepo(<String>[
  'toolkit',
  'dovetail_shortcut_channel',
  'rust',
]);

String _slice(TargetArch arch) => p.join(
  _rust,
  'target',
  arch.rustTriple(TargetOs.macos),
  'release',
  'libdesktop_shortcut_channel.dylib',
);

bool _slicesBuilt() =>
    TargetArch.values.every((TargetArch a) => File(_slice(a)).existsSync());

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_inspect'));
  tearDown(() => root.deleteSync(recursive: true));

  group('ArtifactInspector.kindOf', () {
    test('should read the kind from the extension', () {
      expect(ArtifactInspector.kindOf('a/b.dmg'), ArtifactKind.diskImage);
      expect(ArtifactInspector.kindOf('a/b.deb'), ArtifactKind.debianPackage);
      expect(ArtifactInspector.kindOf('a/b.rpm'), ArtifactKind.rpmPackage);
      expect(ArtifactInspector.kindOf('a/b.msi'), ArtifactKind.windowsPackage);
      expect(
        ArtifactInspector.kindOf('a/b.exe'),
        ArtifactKind.windowsInstaller,
      );
      expect(ArtifactInspector.kindOf('a/B.app'), ArtifactKind.macosBundle);
    });

    test('should read a Mach-O with no extension by its header', () {
      if (!_slicesBuilt()) {
        markTestSkipped('build both apple slices first');
        return;
      }
      final String stripped = p.join(root.path, 'noextension');
      File(_slice(TargetArch.arm64)).copySync(stripped);
      expect(ArtifactInspector.kindOf(stripped), ArtifactKind.machO);
    });

    test('a text file should not be mistaken for an artefact', () {
      final String text = p.join(root.path, 'notes');
      File(text).writeAsStringSync('hello');
      expect(ArtifactInspector.kindOf(text), ArtifactKind.unknown);
    });
  });

  group('ArtifactInspector.architectureInName', () {
    test('should read every spelling a bundler writes', () {
      expect(
        ArtifactInspector.architectureInName('client_2.1.0_amd64.deb'),
        TargetArch.x86_64,
      );
      expect(
        ArtifactInspector.architectureInName('client-2.1.0-1.aarch64.rpm'),
        TargetArch.arm64,
      );
      expect(
        ArtifactInspector.architectureInName('client_2.1.0_x64.msi'),
        TargetArch.x86_64,
      );
      expect(
        ArtifactInspector.architectureInName('client_2.1.0_arm64.dmg'),
        TargetArch.arm64,
      );
    });

    test('a universal name should claim no single architecture', () {
      expect(
        ArtifactInspector.architectureInName('client_2.1.0_universal.dmg'),
        isNull,
      );
    });

    test('a name with no architecture should claim none', () {
      expect(ArtifactInspector.architectureInName('client_2.1.0.dmg'), isNull);
    });
  });

  group('ArtifactInspector on real Mach-O', () {
    test('should report the architecture a thin slice carries', () {
      if (!_slicesBuilt()) {
        markTestSkipped('build both apple slices first');
        return;
      }

      final ArtifactInspection inspection = const ArtifactInspector().inspect(
        _slice(TargetArch.x86_64),
      );
      expect(inspection.kind, ArtifactKind.machO);
      expect(inspection.architectures, <TargetArch>{TargetArch.x86_64});
      expect(inspection.notes, contains('thin header'));
    });

    test('should report a fat header as both architectures', () async {
      if (!_slicesBuilt()) {
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

      final ArtifactInspection inspection = const ArtifactInspector().inspect(
        fat,
      );
      expect(inspection.architectures, hasLength(2));
      expect(inspection.notes, contains('fat header'));
      expect(inspection.nameAgreesWithContent, true);
    });

    test('a name that disagrees with the bytes should be caught', () {
      if (!_slicesBuilt()) {
        markTestSkipped('build both apple slices first');
        return;
      }

      final String lying = p.join(root.path, 'client_2.1.0_arm64.dylib');
      File(_slice(TargetArch.x86_64)).copySync(lying);

      final ArtifactInspection inspection = const ArtifactInspector().inspect(
        lying,
      );
      expect(inspection.declaredArchitecture, TargetArch.arm64);
      expect(inspection.architectures, <TargetArch>{TargetArch.x86_64});
      expect(
        inspection.nameAgreesWithContent,
        false,
        reason:
            'six targets means six artefacts nobody eyeballs; the only thing '
            'that catches a swapped file is reading it',
      );
      expect(inspection.lines.join('\n'), contains('DISAGREES'));
    });

    test('a name that agrees with the bytes should pass', () {
      if (!_slicesBuilt()) {
        markTestSkipped('build both apple slices first');
        return;
      }

      final String honest = p.join(root.path, 'client_2.1.0_x86_64.dylib');
      File(_slice(TargetArch.x86_64)).copySync(honest);
      expect(
        const ArtifactInspector().inspect(honest).nameAgreesWithContent,
        true,
      );
    });
  });

  group('ArtifactInspector on a bundle', () {
    test('should warn when only part of a bundle is universal', () async {
      if (!_slicesBuilt()) {
        markTestSkipped('build both apple slices first');
        return;
      }

      final String app = p.join(root.path, 'Half.app');
      final String macos = p.join(app, 'Contents', 'MacOS');
      Directory(macos).createSync(recursive: true);

      await const UniversalBinary(runner: SystemProcessRunner()).merge(
        slices: <TargetArch, String>{
          for (final TargetArch arch in TargetArch.values) arch: _slice(arch),
        },
        output: p.join(macos, 'fat'),
      );
      File(_slice(TargetArch.arm64)).copySync(p.join(macos, 'thin'));

      final ArtifactInspection inspection = const ArtifactInspector().inspect(
        app,
      );
      expect(inspection.architectures, <TargetArch>{TargetArch.arm64});
      expect(inspection.notes.join(' '), contains('universal only in part'));
    });

    test('a bundle whose binaries all match should carry no warning', () {
      if (!_slicesBuilt()) {
        markTestSkipped('build both apple slices first');
        return;
      }

      final String app = p.join(root.path, 'Thin.app');
      final String macos = p.join(app, 'Contents', 'MacOS');
      Directory(macos).createSync(recursive: true);
      File(_slice(TargetArch.arm64)).copySync(p.join(macos, 'one'));
      File(_slice(TargetArch.arm64)).copySync(p.join(macos, 'two'));

      final ArtifactInspection inspection = const ArtifactInspector().inspect(
        app,
      );
      expect(inspection.architectures, <TargetArch>{TargetArch.arm64});
      expect(inspection.notes.join(' '), isNot(contains('only in part')));
    });
  });

  group('ArtifactInspector on what it cannot read', () {
    test('every unread format should say so', () {
      for (final String name in <String>['a.deb', 'a.rpm', 'a.msi', 'a.exe']) {
        final String path = p.join(root.path, name);
        File(path).writeAsStringSync('not really that format');
        expect(
          const ArtifactInspector().inspect(path).notes.join(' '),
          contains('only read the name'),
          reason: name,
        );
      }
    });

    test('should say plainly that it only read the name', () {
      final String deb = p.join(root.path, 'client_2.1.0_arm64.deb');
      File(deb).writeAsStringSync('not really a deb');

      final ArtifactInspection inspection = const ArtifactInspector().inspect(
        deb,
      );
      expect(inspection.kind, ArtifactKind.debianPackage);
      expect(inspection.architectures, isEmpty);
      expect(inspection.declaredArchitecture, TargetArch.arm64);
      expect(
        inspection.nameAgreesWithContent,
        true,
        reason: 'it cannot disagree with content it never read',
      );
      expect(
        inspection.notes.join(' '),
        contains('only read the name'),
        reason:
            'the note was conditioned on an unknown kind, so a .deb — whose '
            'kind is known and whose bytes are not read — printed nothing and '
            'a passing line read as a verified one',
      );
      expect(inspection.lines.join('\n'), contains('note'));
    });
  });
}
