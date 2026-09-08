import 'dart:io';

import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

bool _onPath(String name) =>
    Process.runSync('which', <String>[name]).exitCode == 0;

void main() {
  group('a binary that only shares the name', () {
    test('should be called wrong, not broken', () async {
      if (!Platform.isMacOS || !_onPath('signtool')) {
        markTestSkipped('needs the nss signtool this machine happens to carry');
        return;
      }

      final ToolReport report = await const CommandProbe(
        name: 'signtool',
        purpose: 'signs the binaries and the installer',
        trivialArguments: <String>['/?'],
        identity: 'Authenticode',
      ).probe();

      expect(
        report.status,
        ToolStatus.impostor,
        reason:
            'the signtool on this PATH is nss, which signs jar files; calling '
            'it broken suggests fixing it, and it is not the tool at all',
      );
      expect(report.line, startsWith('wrong    signtool'));
      expect(report.detail, contains('not the tool this step needs'));
      expect(report.isUsable, false);
    });

    test('the detail should quote what the program says it is', () async {
      final ToolReport report = await const CommandProbe(
        name: 'echo',
        purpose: 'stands in for a tool with the wrong identity',
        trivialArguments: <String>['I am a jar signer'],
        identity: 'Authenticode',
      ).probe();

      expect(report.status, ToolStatus.impostor);
      expect(report.detail, contains('I am a jar signer'));
    });

    test(
      'a matching identity should pass through to the usual check',
      () async {
        final ToolReport report = await const CommandProbe(
          name: 'echo',
          purpose: 'stands in for the right tool',
          trivialArguments: <String>['Authenticode signing'],
          identity: 'Authenticode',
        ).probe();

        expect(report.status, ToolStatus.usable);
        expect(report.isUsable, true);
      },
    );

    test('a probe with no identity should behave as it always did', () async {
      final ToolReport report = await const CommandProbe(
        name: 'echo',
        purpose: 'no identity declared',
        trivialArguments: <String>['anything at all'],
      ).probe();

      expect(report.status, ToolStatus.usable);
    });

    test('an absent binary is still absent, never an impostor', () async {
      final ToolReport report = await const CommandProbe(
        name: 'dovetail_no_such_tool',
        purpose: 'nothing answers to this',
        trivialArguments: <String>['--version'],
        identity: 'anything',
      ).probe();

      expect(report.status, ToolStatus.absent);
    });
  });

  group('which signer the windows target asks for', () {
    test('a host that is not windows should be offered osslsigncode', () {
      final Iterable<String> names = Doctor.probesFor(
        'windows',
      ).map((ToolProbe probe) => probe.name);

      if (Platform.isWindows) {
        expect(names, contains('signtool'));
        return;
      }

      expect(
        names,
        contains('osslsigncode'),
        reason:
            'signtool ships with the Windows SDK and exists nowhere else, so '
            'probing for it off Windows can only ever find something that is '
            'not it',
      );
      expect(names, isNot(contains('signtool')));
    });

    test(
      'a tool that reports its version on a non-zero exit still counts',
      () async {
        if (!_onPath('osslsigncode')) {
          markTestSkipped('osslsigncode is not installed');
          return;
        }

        final ToolReport report = await const CommandProbe(
          name: 'osslsigncode',
          purpose: 'signs the Windows binaries without a Windows machine',
          trivialArguments: <String>['--version'],
          identity: 'osslsigncode',
          acceptsNonZeroExit: true,
        ).probe();

        expect(report.status, ToolStatus.usable);
      },
    );
  });
}
