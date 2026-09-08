import 'dart:io';
import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('present but broken, proven without depending on this machine', () {
    late Directory scratch;

    setUp(() => scratch = Directory.systemTemp.createTempSync('probe'));
    tearDown(() => scratch.deleteSync(recursive: true));

    String toolThat(String body) {
      final String path = p.join(scratch.path, 'faketool');
      File(path).writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', <String>['755', path]);
      return path;
    }

    test(
      'a tool that exits non-zero should be unusable, with its own words',
      () async {
        final ToolReport report = await CommandProbe(
          name: toolThat('echo "it aborted" >&2; exit 3'),
          purpose: 'a tool that is installed and does not work',
          trivialArguments: const <String>['--probe'],
        ).probe();

        expect(report.status, ToolStatus.unusable);
        expect(report.detail, contains('it aborted'));
        expect(report.line, startsWith('broken'));
      },
    );

    test(
      'a tool that exits zero and produces nothing should be unusable',
      () async {
        final ToolReport report = await CommandProbe(
          name: toolThat('exit 0'),
          purpose: 'a tool that reports success it did not earn',
          trivialArguments: const <String>['--probe'],
          expectsFile: 'expected.out',
        ).probe();

        expect(
          report.status,
          ToolStatus.unusable,
          reason:
              'exit zero without the artefact is the case the probe exists for: '
              'a build would report success it did not earn',
        );
      },
    );

    test('a tool that produces what it promised should be usable', () async {
      final ToolReport report = await CommandProbe(
        name: toolThat('printf x > expected.out'),
        purpose: 'a tool that works',
        trivialArguments: const <String>['--probe'],
        expectsFile: 'expected.out',
      ).probe();

      expect(report.status, ToolStatus.usable);
      expect(report.line, startsWith('ok'));
    });

    test('a tool that is not installed should be absent, not broken', () async {
      final ToolReport report = await const CommandProbe(
        name: 'a-tool-nobody-has-installed',
        purpose: 'nothing',
        trivialArguments: <String>['--version'],
      ).probe();

      expect(report.status, ToolStatus.absent);
    });
  });

  group('the tools the pipeline actually runs', () {
    test('minisign should be probed on every target', () {
      for (final String target in <String>['macos', 'linux', 'windows']) {
        expect(
          Doctor.probesFor(target).map((ToolProbe probe) => probe.name),
          contains('minisign'),
          reason:
              '$target: dovetail release signs the update artefact on '
              'whichever runner builds it, so the tool matters everywhere',
        );
      }
    });

    test('lipo should be probed on macos and nowhere else', () {
      expect(
        Doctor.probesFor('macos').map((ToolProbe probe) => probe.name),
        contains('lipo'),
      );
      for (final String target in <String>['linux', 'windows']) {
        expect(
          Doctor.probesFor(target).map((ToolProbe probe) => probe.name),
          isNot(contains('lipo')),
          reason: target,
        );
      }
    });
  });

  test(
    'an absent tool should be reported as missing, with its purpose',
    () async {
      const CommandProbe sut = CommandProbe(
        name: 'a_tool_that_does_not_exist_here',
        purpose: 'builds nothing',
        trivialArguments: <String>['--version'],
      );

      final ToolReport report = await sut.probe();

      expect(report.status, ToolStatus.absent);
      expect(report.line, contains('missing'));
      expect(report.line, contains('builds nothing'));
    },
  );

  test(
    'a tool that answers should be reported as usable, with its path',
    () async {
      const CommandProbe sut = CommandProbe(
        name: 'echo',
        purpose: 'prints',
        trivialArguments: <String>['probe'],
      );

      final ToolReport report = await sut.probe();

      expect(report.status, ToolStatus.usable);
      expect(report.path, isNotNull);
      expect(report.line, startsWith('ok'));
    },
  );

  test(
    'a tool that fails a trivial input should be reported as broken',
    () async {
      const CommandProbe sut = CommandProbe(
        name: 'false',
        purpose: 'always refuses',
        trivialArguments: <String>[],
      );

      final ToolReport report = await sut.probe();

      expect(report.status, ToolStatus.unusable);
      expect(report.line, startsWith('broken'));
    },
  );

  test('a tool that exits zero without producing the file is broken', () async {
    const CommandProbe sut = CommandProbe(
      name: 'true',
      purpose: 'exits zero and does nothing',
      trivialArguments: <String>[],
      expectsFile: 'never_written.out',
    );

    final ToolReport report = await sut.probe();

    expect(
      report.status,
      ToolStatus.unusable,
      reason:
          'exit zero is not proof; a bundler that trusts it reports a success '
          'it did not earn',
    );
  });

  test('an input file should be written before the tool runs', () async {
    const CommandProbe sut = CommandProbe(
      name: 'cat',
      purpose: 'reads what the probe wrote',
      trivialArguments: <String>['input.txt'],
      inputFiles: <String, String>{'input.txt': 'hello'},
    );

    final ToolReport report = await sut.probe();

    expect(report.status, ToolStatus.usable);
  });

  test('the probe list should differ per target', () {
    expect(
      Doctor.probesFor('windows').map((ToolProbe p) => p.name),
      contains('makensis'),
    );
    expect(
      Doctor.probesFor('macos').map((ToolProbe p) => p.name),
      containsAll(<String>['codesign', 'hdiutil', 'xcrun', 'ditto']),
    );
    expect(
      Doctor.probesFor('linux').map((ToolProbe p) => p.name),
      contains('rpmbuild'),
    );
    expect(Doctor.probesFor('haiku'), isEmpty);
  });

  test('render should say so when no probe is defined', () {
    expect(Doctor.render(const <ToolReport>[]), contains('no probe'));
  });

  test('allUsable should be false for an empty report, not vacuously true', () {
    expect(
      Doctor.allUsable(const <ToolReport>[]),
      false,
      reason: 'an empty report means nothing was checked, not that all is well',
    );
  });

  test('the macOS toolchain on this machine should be usable', () async {
    if (!Platform.isMacOS) {
      markTestSkipped(
        'missing hdiutil (builds the dmg) and codesign (signs the app '
        'bundle); the macOS toolchain only exists on macOS',
      );
      return;
    }

    final List<ToolReport> reports = await Doctor.run(
      Doctor.probesFor('macos'),
    );

    expect(Doctor.allUsable(reports), true, reason: Doctor.render(reports));
  });

  test('the windows toolchain should be reported honestly from here', () async {
    if (!Platform.isMacOS) {
      markTestSkipped(
        'missing wixl (compiles the MSI) and makensis (the NSIS trap that '
        'aborts here); this honest report describes the macOS machine',
      );
      return;
    }

    final List<ToolReport> reports = await Doctor.run(
      Doctor.probesFor('windows'),
    );

    // Not "no Windows tool works here" — wixl does, and saying otherwise was
    // how doctor came to report `missing wix` on a machine that builds the
    // MSI. These are the ones that genuinely need Windows, or are broken.
    // "Broken" includes the trap that founded the real-script probe: a
    // four-line script compiles here while the generated installer aborts,
    // so a trivial probe says usable for a host that cannot build.
    const Set<String> needsWindows = <String>{'makensis', 'wix', 'signtool'};
    expect(
      reports
          .where((ToolReport r) => needsWindows.contains(r.name))
          .any((ToolReport r) => r.isUsable),
      false,
      reason:
          'these need a Windows host or are broken here; wixl and '
          'osslsigncode are the ones that cross-build, and they work',
    );
    expect(
      reports
          .where((ToolReport r) => r.name == 'wixl')
          .every((ToolReport r) => r.isUsable),
      true,
      reason:
          'this machine can produce the Windows MSI, and doctor must say so',
    );
    expect(
      reports.any((ToolReport r) => r.status == ToolStatus.unusable),
      true,
      reason:
          'makensis is installed here and aborts on the real generated '
          'installer, which is exactly the case the probe exists to catch',
    );
    expect(reports.map((ToolReport r) => r.name), contains('minisign'));
  });
  group('the MSI backend it probes', () {
    test('should be the one the bundler would actually invoke', () {
      final List<String> named = Doctor.probesFor(
        'windows',
      ).map((ToolProbe probe) => probe.name).toList();

      final bool onWindows = MsiBackend.forHost().needsWindows;
      expect(
        named,
        contains(onWindows ? 'wix' : 'wixl'),
        reason:
            'MsiBackend.forHost picks wixl off Windows, so probing wix there '
            'reported "missing wix" on a machine that builds the MSI fine — '
            'and never probed the binary that would really run',
      );
      expect(named, isNot(contains(onWindows ? 'wixl' : 'wix')));
    });
  });
}
