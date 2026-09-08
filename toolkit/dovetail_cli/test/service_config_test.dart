import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

const String _head = '''
identifier: com.example.demo
name: Demo
manufacturer: Example Ltda
targets: [linux-x86_64]
''';

DovetailConfig parse(String service) =>
    DovetailConfig.parse('$_head\nservice:\n$service');

const String _minimal = '''
  name: demo-helper.service
  description: Privileged helper for the tunnel
  exec-start: /usr/lib/demo/demo-helper
''';

Matcher refusalSaying(Object? message, {Object? remedy}) => throwsA(
  isA<ConfigFailure>()
      .having((ConfigFailure f) => f.message, 'message', message)
      .having(
        (ConfigFailure f) => f.remedy ?? '',
        'remedy',
        remedy ?? anything,
      ),
);

void main() {
  group('the unit it builds', () {
    test('a minimal service should parse', () {
      final ServiceConfig service = parse(_minimal).service!;

      expect(service.unit.fileName, 'demo-helper.service');
      expect(service.unit.execStart, '/usr/lib/demo/demo-helper');
      expect(service.policy, isNull);
      expect(service.scripts.unitFileName, 'demo-helper.service');
    });

    test('a name that is not a unit file should be refused', () {
      expect(
        () => parse('  name: demo-helper\n  description: d\n  exec-start: /x'),
        refusalSaying(contains('demo-helper'), remedy: contains('.service')),
        reason: 'systemd loads a unit by its file name',
      );
    });

    test('the scripts should always name the unit the package installs', () {
      final ServiceConfig service = parse(_minimal).service!;

      expect(service.scripts.unitFileName, service.unit.fileName);
    });

    test('capabilities should reach both the bounding set and ambient', () {
      final ServiceConfig service = parse(
        '$_minimal  capabilities: [CAP_NET_ADMIN, CAP_NET_RAW]\n',
      ).service!;

      expect(service.unit.capabilityBoundingSet, <String>{
        'CAP_NET_ADMIN',
        'CAP_NET_RAW',
      });
      expect(
        service.unit.ambientCapabilities,
        service.unit.capabilityBoundingSet,
        reason:
            'an ambient capability outside the bounding set is dropped in '
            'silence, and the helper starts without the privilege it needs',
      );
    });

    test('a directory should take a default mode, or the one given', () {
      expect(
        parse(
          '$_minimal  runtime-directory: demo\n',
        ).service!.unit.runtimeDirectory!.mode,
        '0750',
      );
      expect(
        parse(
          '$_minimal  state-directory:\n    name: demo\n    mode: "0700"\n',
        ).service!.unit.stateDirectory!.mode,
        '0700',
      );
    });

    test('an absolute directory should be refused with the reason', () {
      expect(
        () => parse('$_minimal  runtime-directory: 12\n'),
        refusalSaying(contains('runtime-directory'), remedy: contains('/run')),
      );
    });

    test('a missing field should name itself', () {
      for (final String field in <String>[
        'name',
        'description',
        'exec-start',
      ]) {
        final String without = _minimal
            .split('\n')
            .where((String line) => !line.trim().startsWith('$field:'))
            .join('\n');

        expect(
          () => parse(without),
          refusalSaying(contains(field)),
          reason: field,
        );
      }
    });
  });

  group('the polkit policy', () {
    const String polkitSection = '''
  polkit:
    action: com.example.demo.manage
    vendor: Example Ltda
    description: Manage the connection
    message: Authentication is required
''';

    test('a well-formed policy should carry one action', () {
      final PolkitPolicy policy = parse(
        '$_minimal$polkitSection',
      ).service!.policy!;

      expect(policy.namespace, 'com.example.demo');
      expect(policy.actions, hasLength(1));
      expect(policy.actions.single.id, 'com.example.demo.manage');
    });

    test('an action outside the identifier namespace should be refused', () {
      expect(
        () => parse(
          '$_minimal  polkit:\n    action: org.other.manage\n'
          '    vendor: V\n    description: d\n    message: m\n',
        ),
        refusalSaying(
          contains('outside the "com.example.demo" namespace'),
          remedy: contains('never apply'),
        ),
        reason:
            'polkit names the file after the namespace, so an action declared '
            'outside it installs and is never consulted',
      );
    });

    test('a policy with no vendor should be refused', () {
      expect(
        () => parse(
          '$_minimal  polkit:\n    action: com.example.demo.manage\n'
          '    description: d\n    message: m\n',
        ),
        refusalSaying(contains('vendor')),
      );
    });
  });

  group('what the config leaves alone', () {
    test('no service section should mean no unit at all', () {
      expect(DovetailConfig.parse(_head).service, isNull);
    });

    test('purge paths should reach the scripts', () {
      final ServiceConfig service = parse(
        '$_minimal  purge-paths: [/var/lib/demo]\n',
      ).service!;

      expect(service.scripts.purgePaths, <String>['/var/lib/demo']);
    });

    test('a relative purge path should be refused by the bundler', () {
      expect(
        () => parse('$_minimal  purge-paths: [var/lib/demo]\n'),
        throwsA(anything),
        reason:
            'purge runs as root at removal time, and a relative path there is '
            'resolved against whatever directory dpkg happens to be in',
      );
    });
  });
}
