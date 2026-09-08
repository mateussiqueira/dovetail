import 'dart:ffi';
import 'dart:io';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The host's own build target, or null when the host is one the bundler
/// does not build for (32-bit or a phone platform). The probe reads the real
/// `rustup target list --installed`, so asking it about anything other than
/// the host triple would report "absent" on every machine but the one the
/// triple belongs to.
(TargetOs, TargetArch)? get _hostTarget => switch (Abi.current()) {
  Abi.macosArm64 => (TargetOs.macos, TargetArch.arm64),
  Abi.macosX64 => (TargetOs.macos, TargetArch.x86_64),
  Abi.linuxX64 => (TargetOs.linux, TargetArch.x86_64),
  Abi.linuxArm64 => (TargetOs.linux, TargetArch.arm64),
  Abi.windowsX64 => (TargetOs.windows, TargetArch.x86_64),
  Abi.windowsArm64 => (TargetOs.windows, TargetArch.arm64),
  _ => null,
};

void main() {
  group('RustTargetProbe', () {
    test('should name the triple cargo needs for each of the six', () {
      final Set<String> triples = <String>{
        for (final TargetOs os in TargetOs.values)
          for (final TargetArch arch in TargetArch.values)
            RustTargetProbe(os: os, arch: arch).triple,
      };

      expect(triples, hasLength(6));
      expect(triples, contains('aarch64-pc-windows-msvc'));
      expect(triples, contains('x86_64-unknown-linux-gnu'));
      expect(triples, contains('aarch64-apple-darwin'));
    });

    test('should report the host target as installed', () async {
      final (TargetOs, TargetArch)? host = _hostTarget;
      if (host == null) {
        markTestSkipped('this host has no target the bundler builds');
        return;
      }

      final ToolReport report = await RustTargetProbe(
        os: host.$1,
        arch: host.$2,
      ).probe();

      expect(report.status, ToolStatus.usable, reason: report.detail ?? '');
    });

    test(
      'an absent target should carry the command that installs it',
      () async {
        final Directory scratch = Directory.systemTemp.createTempSync('rustup');
        addTearDown(() => scratch.deleteSync(recursive: true));

        final String fake = p.join(scratch.path, 'rustup');
        File(fake).writeAsStringSync('#!/bin/sh\necho x86_64-apple-darwin\n');
        Process.runSync('chmod', <String>['755', fake]);

        final ToolReport report = await RustTargetProbe(
          os: TargetOs.windows,
          arch: TargetArch.arm64,
          rustup: fake,
        ).probe();

        expect(
          report.status,
          ToolStatus.absent,
          reason:
              'the injected rustup lists one target and it is not this one; '
              'reading the real machine made the assertion vacuous wherever '
              'the target happened to be installed',
        );
        expect(report.detail, 'rustup target add aarch64-pc-windows-msvc');
        expect(report.line, contains('rustup target add'));
      },
    );

    test('a target the injected rustup lists should read as usable', () async {
      final Directory scratch = Directory.systemTemp.createTempSync('rustup2');
      addTearDown(() => scratch.deleteSync(recursive: true));

      final String fake = p.join(scratch.path, 'rustup');
      File(fake).writeAsStringSync('#!/bin/sh\necho aarch64-pc-windows-msvc\n');
      Process.runSync('chmod', <String>['755', fake]);

      final ToolReport report = await RustTargetProbe(
        os: TargetOs.windows,
        arch: TargetArch.arm64,
        rustup: fake,
      ).probe();

      expect(report.status, ToolStatus.usable);
    });

    test('a rustup that fails should read as unusable, not absent', () async {
      final Directory scratch = Directory.systemTemp.createTempSync('rustup3');
      addTearDown(() => scratch.deleteSync(recursive: true));

      final String fake = p.join(scratch.path, 'rustup');
      File(fake).writeAsStringSync(
        '#!/bin/sh\necho "the toolchain is not installed" >&2\nexit 1\n',
      );
      Process.runSync('chmod', <String>['755', fake]);

      final ToolReport report = await RustTargetProbe(
        os: TargetOs.linux,
        arch: TargetArch.x86_64,
        rustup: fake,
      ).probe();

      expect(report.status, ToolStatus.unusable);
      expect(report.detail, contains('not installed'));
    });

    test('no rustup at all should read as absent, not as broken', () async {
      final ToolReport report = await const RustTargetProbe(
        os: TargetOs.linux,
        arch: TargetArch.x86_64,
        rustup: 'rustup-that-is-not-installed',
      ).probe();

      expect(report.status, ToolStatus.absent);
    });

    test('the doctor should only ask about a target when given an arch', () {
      expect(Doctor.probesFor('windows').whereType<RustTargetProbe>(), isEmpty);
      expect(
        Doctor.probesFor(
          'windows',
          arch: TargetArch.arm64,
        ).whereType<RustTargetProbe>().single.triple,
        'aarch64-pc-windows-msvc',
      );
    });

    test('the arch should not change which platform tools are asked for', () {
      expect(
        Doctor.probesFor('macos').map((ToolProbe probe) => probe.name),
        Doctor.probesFor(
          'macos',
          arch: TargetArch.x86_64,
        ).whereType<CommandProbe>().map((ToolProbe probe) => probe.name),
      );
    });
  });
}
