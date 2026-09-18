import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

DovetailConfig configWith(String targets, {String extra = ''}) =>
    DovetailConfig.parse('''
identifier: com.example.demo
name: Demo Client
manufacturer: Example Ltda
targets: [$targets]
$extra
''');

ShipPlan planFor(
  String targets, {
  String host = 'macos',
  String extra = '',
  bool build = true,
  String? windowsFormat = 'msi',
  Map<String, String>? environment,
  ShipChannel channel = ShipChannel.release,
}) => ShipPlan.of(
  config: configWith(targets, extra: extra),
  version: '4.2.0',
  host: host,
  binary: 'demo_app',
  build: build,
  windowsFormat: windowsFormat,
  environment: environment,
  channel: channel,
);

const String _systemRoute =
    'service:\n'
    '  macos:\n'
    '    label: com.example.demo.helper\n'
    '    program: demo-helper\n'
    '    binary: target/release/demo-helper\n'
    '    route: system\n'
    '    instructions: packaging/LEIA-ME.txt\n';

const String _systemRouteWithoutInstructions =
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

const String _update =
    'update:\n'
    '  key: keys/update.key\n'
    '  base-url: https://example.com/releases\n';

List<String> labelsOf(ShipPlan plan) =>
    plan.steps.map((ShipStep step) => step.label).toList();

List<String> argumentsOf(ShipPlan plan, String label) =>
    plan.steps.firstWhere((ShipStep step) => step.label == label).arguments;

void main() {
  group('the release channel is what it always was', () {
    test('macos keeps the four steps and the dmg default', () {
      final ShipPlan plan = planFor('darwin-aarch64');
      expect(labelsOf(plan), <String>[
        'build macos',
        'sign darwin-aarch64',
        'bundle darwin-aarch64',
        'sign dmg darwin-aarch64',
        'archive darwin-aarch64',
      ]);
      // O build do release nao pede `--no-release`, e o bundle nao pede
      // formato nenhum — o dmg e o padrao dele.
      expect(argumentsOf(plan, 'build macos'), <String>['--target', 'macos']);
      expect(
        argumentsOf(plan, 'bundle darwin-aarch64'),
        isNot(contains('--macos-format')),
      );
      // O download e o dmg; o manifesto publica o tar.
      expect(plan.downloads['darwin-aarch64'], endsWith('.dmg'));
      expect(plan.artifacts['darwin-aarch64'], endsWith('.tar.gz'));
    });
  });

  group('the internal channel', () {
    test('builds debug and signs ad-hoc, and writes no manifest', () {
      final ShipPlan plan = planFor(
        'darwin-aarch64',
        channel: ShipChannel.internal,
      );
      expect(labelsOf(plan), <String>[
        'build macos',
        'sign darwin-aarch64',
        'bundle darwin-aarch64',
      ]);
      expect(argumentsOf(plan, 'build macos'), <String>[
        '--target',
        'macos',
        '--no-release',
      ]);
      // O app que o sign assina e o do diretorio Debug, o mesmo que o bundle
      // empacota — senao os dois passos apontariam para builds diferentes.
      expect(
        argumentsOf(plan, 'sign darwin-aarch64'),
        contains('build/macos/Build/Products/Debug/demo_app.app'),
      );
      expect(argumentsOf(plan, 'sign darwin-aarch64'), contains('--ad-hoc'));
      expect(
        argumentsOf(plan, 'bundle darwin-aarch64'),
        contains('build/macos/Build/Products/Debug/demo_app.app'),
      );
      expect(plan.artifacts, isEmpty);
      expect(plan.downloads['darwin-aarch64'], endsWith('.dmg'));
    });

    test('a system-route daemon is installed by the pkg inside the dmg', () {
      final ShipPlan plan = planFor(
        'darwin-aarch64',
        extra: _systemRoute,
        channel: ShipChannel.internal,
      );
      expect(plan.refusals, isEmpty);
      expect(
        argumentsOf(plan, 'bundle darwin-aarch64'),
        containsAllInOrder(<String>['--macos-format', 'pkg-dmg']),
      );
      expect(plan.downloads['darwin-aarch64'], endsWith('.dmg'));
      expect(plan.artifacts, isEmpty);
      // A linha honesta: sem Developer ID Installer, o Finder recusa o pkg.
      expect(plan.notices, hasLength(1));
      expect(plan.notices.single, contains('sudo installer -pkg'));
      expect(plan.notices.single, contains('.dmg'));
    });

    test('a system-route daemon with no instructions is refused', () {
      final ShipPlan plan = planFor(
        'darwin-aarch64',
        extra: _systemRouteWithoutInstructions,
        channel: ShipChannel.internal,
      );
      expect(plan.refusals.single, contains('instructions'));
    });

    test(
      'a bundled-route daemon is refused, because ad-hoc has no Team ID',
      () {
        final ShipPlan plan = planFor(
          'darwin-aarch64',
          extra: _bundledRoute,
          channel: ShipChannel.internal,
        );
        expect(plan.refusals.single, contains('ad-hoc'));
        expect(plan.refusals.single, contains('SMAppService'));
      },
    );

    test('an update section is refused instead of trusted', () {
      final ShipPlan plan = planFor(
        'darwin-aarch64',
        extra: _update,
        channel: ShipChannel.internal,
      );
      expect(plan.refusals.single, contains('no updater manifest'));
      expect(labelsOf(plan), isNot(contains('release 4.2.0')));
    });

    test('linux builds debug and publishes no manifest', () {
      final ShipPlan plan = planFor(
        'linux-x86_64',
        host: 'linux',
        channel: ShipChannel.internal,
      );
      expect(argumentsOf(plan, 'build linux'), <String>[
        '--target',
        'linux',
        '--no-release',
      ]);
      expect(plan.artifacts, isEmpty);
      expect(plan.downloads['linux-x86_64'], endsWith('.deb'));
    });
  });

  group('the channel answers honestly about the declared service', () {
    test(
      'release refuses a system-route daemon, because a dmg installs none',
      () {
        final ShipPlan plan = planFor('darwin-aarch64', extra: _systemRoute);
        expect(plan.refusals.single, contains('.dmg'));
        expect(plan.refusals.single, contains('--channel internal'));
      },
    );

    test('release still ships a dmg for a bundled-route daemon', () {
      final ShipPlan plan = planFor('darwin-aarch64', extra: _bundledRoute);
      expect(plan.refusals, isEmpty);
      expect(plan.downloads['darwin-aarch64'], endsWith('.dmg'));
    });
  });
}
