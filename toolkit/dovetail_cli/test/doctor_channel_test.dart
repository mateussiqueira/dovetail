import 'dart:io';

import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

DovetailConfig configWith(String extra) => DovetailConfig.parse('''
identifier: com.example.demo
name: Demo Client
manufacturer: Example Ltda
targets: [darwin-aarch64]
$extra
''');

const String _systemRoute =
    'service:\n'
    '  macos:\n'
    '    label: com.example.demo.helper\n'
    '    program: demo-helper\n'
    '    binary: target/release/demo-helper\n'
    '    route: system\n';

const String _bundledRoute =
    'service:\n'
    '  macos:\n'
    '    label: com.example.demo.helper\n'
    '    program: demo-helper\n'
    '    binary: target/release/demo-helper\n';

Directory builtDaemon() {
  final Directory root = Directory.systemTemp.createTempSync('dovetail_daemon');
  File(p.join(root.path, 'target', 'release', 'demo-helper'))
    ..createSync(recursive: true)
    ..writeAsStringSync('binary');
  return root;
}

ProjectReport reportFor({
  required String extra,
  required ShipChannel channel,
  required String root,
}) => ProjectReport.of(
  config: configWith(extra),
  version: '4.2.0',
  host: 'macos',
  root: root,
  channel: channel,
);

ProjectNote noteOn(ProjectReport report, String subject) =>
    report.notes.firstWhere((ProjectNote note) => note.subject == subject);

void main() {
  late Directory root;

  setUp(() => root = builtDaemon());
  tearDown(() => root.deleteSync(recursive: true));

  test('release says a system-route daemon is not installable, and why', () {
    final ProjectReport report = reportFor(
      extra: _systemRoute,
      channel: ShipChannel.release,
      root: root.path,
    );
    final ProjectNote note = noteOn(report, 'service (macos)');
    expect(note.finding, ProjectFinding.warning);
    expect(note.detail, contains('.dmg'));
    expect(note.detail, contains('--channel internal'));
    // `warn` nao derruba o projeto: o outro canal o entrega.
    expect(report.shipCanRelease, true);
  });

  test('internal says the same daemon is installable by its pkg', () {
    final ProjectReport report = reportFor(
      extra: _systemRoute,
      channel: ShipChannel.internal,
      root: root.path,
    );
    final ProjectNote note = noteOn(report, 'service (macos)');
    expect(note.finding, ProjectFinding.ready);
    expect(note.detail, contains('internal installs it'));
  });

  test('internal says a bundled-route daemon cannot register ad-hoc', () {
    final ProjectReport report = reportFor(
      extra: _bundledRoute,
      channel: ShipChannel.internal,
      root: root.path,
    );
    final ProjectNote note = noteOn(report, 'service (macos)');
    expect(note.finding, ProjectFinding.warning);
    expect(note.detail, contains('ad-hoc'));
    expect(note.detail, contains('Team ID'));
  });

  test('release keeps shipping the bundled route it always did', () {
    final ProjectReport report = reportFor(
      extra: _bundledRoute,
      channel: ShipChannel.release,
      root: root.path,
    );
    final ProjectNote note = noteOn(report, 'service (macos)');
    expect(note.finding, ProjectFinding.ready);
    expect(note.detail, contains('com.example.demo.helper.plist'));
  });

  test('a daemon that was never built is missing on either channel', () {
    final Directory empty = Directory.systemTemp.createTempSync(
      'dovetail_no_daemon',
    );
    addTearDown(() => empty.deleteSync(recursive: true));

    for (final ShipChannel channel in ShipChannel.values) {
      final ProjectReport report = reportFor(
        extra: _systemRoute,
        channel: channel,
        root: empty.path,
      );
      expect(
        noteOn(report, 'service (macos)').finding,
        ProjectFinding.missing,
        reason: 'sem o binario o build recusa, em qualquer canal',
      );
    }
  });
}
