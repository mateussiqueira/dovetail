import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _FakeRunner implements ProcessRunner {
  _FakeRunner({this.exitCode = 0, this.stderr = ''});

  final int exitCode;
  final String stderr;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    String? stdin,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    if (exitCode == 0 && arguments.length > 1) {
      File(
        arguments[1],
      ).writeAsBytesSync(Uint8List.fromList(List<int>.filled(64, 0x73)));
    }
    return ProcessOutcome(exitCode: exitCode, stdout: '', stderr: stderr);
  }
}

Uint8List _elf(int machine) {
  final Uint8List head = Uint8List(64);
  head[0] = 0x7F;
  head[1] = 0x45;
  head[2] = 0x4C;
  head[3] = 0x46;
  head[18] = machine & 0xFF;
  head[19] = (machine >> 8) & 0xFF;
  return head;
}

void main() {
  late Directory root;
  late String app;
  late String runtime;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_appimage');
    app = p.join(root.path, 'bundle');
    Directory(p.join(app, 'lib')).createSync(recursive: true);
    File(p.join(app, 'client')).writeAsStringSync('#!/bin/sh\nexec true\n');
    File(p.join(app, 'lib', 'libapp.so')).writeAsStringSync('so');
    File(p.join(app, 'data', 'icudtl.dat'))
      ..createSync(recursive: true)
      ..writeAsStringSync('data');

    runtime = p.join(root.path, 'runtime-aarch64');
    File(runtime).writeAsBytesSync(_elf(0xB7));
  });

  tearDown(() => root.deleteSync(recursive: true));

  BundleSpec specOf() => BundleSpec(
    productName: 'Example',
    manufacturer: 'Example Ltda',
    identifier: 'io.example.client',
    version: AppVersion.parse('1.2.0'),
    mainBinaryName: 'client',
    appDirectory: app,
    outputDirectory: p.join(root.path, 'out'),
  );

  group('the ELF header it reads', () {
    test('should name aarch64 and x86_64 by their machine code', () {
      File(p.join(root.path, 'a')).writeAsBytesSync(_elf(0xB7));
      File(p.join(root.path, 'x')).writeAsBytesSync(_elf(0x3E));

      expect(ElfHeader.read(p.join(root.path, 'a')).arch, TargetArch.arm64);
      expect(ElfHeader.read(p.join(root.path, 'x')).arch, TargetArch.x86_64);
    });

    test('should refuse a file that is not an ELF at all', () {
      File(
        p.join(root.path, 'page'),
      ).writeAsStringSync('<!doctype html><title>404</title>');

      expect(
        () => ElfHeader.read(p.join(root.path, 'page')),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.message,
            'message',
            contains('ELF magic number'),
          ),
        ),
      );
    });

    test('should refuse a machine it does not build for', () {
      File(p.join(root.path, 'riscv')).writeAsBytesSync(_elf(0xF3));

      expect(
        () => ElfHeader.read(p.join(root.path, 'riscv')),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('the launcher it writes', () {
    test('should resolve its own directory before it execs', () {
      final String script = AppRun.forBinary('client');

      expect(script, startsWith('#!/bin/sh'));
      expect(
        script,
        contains(r'readlink -f "$0"'),
        reason:
            'an AppImage is launched through a symlink as often as not, and '
            'dirname of the link resolves to the wrong place',
      );
      expect(script, contains(r'exec "$here/usr/bin/client" "$@"'));
    });

    test('a bundled desktop entry should carry a relative Exec', () {
      final DesktopEntry entry = DesktopEntry.insideBundle(specOf());

      expect(entry.render(), contains('Exec=client'));
    });

    test('a bundled desktop entry should refuse an absolute Exec', () {
      expect(
        () => DesktopEntry(
          appId: 'io.example.client',
          name: 'Example',
          exec: '/usr/lib/client/client',
          bundled: true,
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('mounts itself'),
          ),
        ),
      );
    });

    test('an installed desktop entry should still demand an absolute Exec', () {
      expect(
        () => DesktopEntry(
          appId: 'io.example.client',
          name: 'Example',
          exec: 'client',
        ),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('the AppImage it builds', () {
    test('should refuse to invent a runtime, and say where to get one', () {
      expect(
        () => AppImageBundler(
          runner: _FakeRunner(),
          arch: TargetArch.arm64,
        ).bundle(specOf()),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            allOf(contains('runtime-aarch64'), contains('type2-runtime')),
          ),
        ),
      );
    });

    test('should refuse a runtime built for the other architecture', () {
      File(runtime).writeAsBytesSync(_elf(0x3E));

      expect(
        () => AppImageBundler(
          runner: _FakeRunner(),
          arch: TargetArch.arm64,
          runtimePath: runtime,
        ).bundle(specOf()),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('cannot execute binary file'),
          ),
        ),
      );
    });

    test('should name the file the way an AppImage is named', () {
      expect(
        AppImageBundler(
          runner: _FakeRunner(),
          arch: TargetArch.arm64,
          runtimePath: runtime,
        ).fileNameFor(specOf()),
        'client-1.2.0-aarch64.AppImage',
      );
    });

    test('should be the runtime with the filesystem appended to it', () async {
      final _FakeRunner runner = _FakeRunner();
      final String built = await AppImageBundler(
        runner: runner,
        arch: TargetArch.arm64,
        runtimePath: runtime,
      ).bundle(specOf());

      final Uint8List bytes = File(built).readAsBytesSync();
      expect(bytes.length, 64 + 64);
      expect(
        bytes.sublist(0, 4),
        <int>[0x7F, 0x45, 0x4C, 0x46],
        reason: 'the kernel reads the first bytes, so the runtime comes first',
      );
      expect(bytes.sublist(64).every((int byte) => byte == 0x73), true);
    });

    test('should hand mksquashfs the AppDir and no appending', () async {
      final _FakeRunner runner = _FakeRunner();
      await AppImageBundler(
        runner: runner,
        arch: TargetArch.arm64,
        runtimePath: runtime,
      ).bundle(specOf());

      final List<String> call = runner.calls.single;
      expect(call.first, 'mksquashfs');
      expect(call, contains('-noappend'));
      expect(
        call,
        contains('-root-owned'),
        reason:
            'the uid of whoever built it would otherwise travel inside the '
            'image and own every file on the user machine',
      );
    });

    test('a failing mksquashfs should be a refusal that carries why', () async {
      await expectLater(
        AppImageBundler(
          runner: _FakeRunner(exitCode: 1, stderr: 'no space left on device'),
          arch: TargetArch.arm64,
          runtimePath: runtime,
        ).bundle(specOf()),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure failure) => failure.remedy,
            'remedy',
            contains('no space left'),
          ),
        ),
      );
    });

    test('an app directory that is not there should be refused', () {
      final BundleSpec missing = BundleSpec(
        productName: 'Example',
        manufacturer: 'Example Ltda',
        identifier: 'io.example.client',
        version: AppVersion.parse('1.2.0'),
        mainBinaryName: 'client',
        appDirectory: p.join(root.path, 'nowhere'),
        outputDirectory: p.join(root.path, 'out'),
      );

      expect(
        () => AppImageBundler(
          runner: _FakeRunner(),
          arch: TargetArch.arm64,
          runtimePath: runtime,
        ).bundle(missing),
        throwsA(isA<BundleFailure>()),
      );
    });
  });

  group('the file it appends into', () {
    test('should overwrite a file already there, not grow it', () {
      final String head = p.join(root.path, 'head');
      final String tail = p.join(root.path, 'tail');
      final String out = p.join(root.path, 'out.bin');
      File(head).writeAsBytesSync(Uint8List.fromList(<int>[1, 2]));
      File(tail).writeAsBytesSync(Uint8List.fromList(<int>[3]));
      File(out).writeAsBytesSync(Uint8List.fromList(List<int>.filled(99, 9)));

      AppendedImage.write(runtime: head, image: tail, destination: out);

      expect(File(out).readAsBytesSync(), <int>[1, 2, 3]);
    });
  });
}
