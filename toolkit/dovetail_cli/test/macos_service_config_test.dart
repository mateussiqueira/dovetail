import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

/// O daemon do macOS, declarado onde a unit do Linux já era declarada.
///
/// O defeito que esta seção fecha não dava erro em lugar nenhum: sem
/// declaração, o binário do helper não entrava no bundle, o `SMAppService`
/// procurava um property list ausente e a tela dizia "não instalado" sobre
/// algo que nunca foi empacotado.
DovetailConfig _parse(String yaml) => DovetailConfig.parse(
  'identifier: com.example.demo\n'
  'name: Demo\n'
  'manufacturer: Example\n'
  'targets: [darwin-aarch64]\n'
  '$yaml',
  origin: 'dovetail.yaml',
);

const String _macos =
    'service:\n'
    '  macos:\n'
    '    label: com.example.demo.helper\n'
    '    program: demo-helper\n';

void main() {
  group('the daemon it declares', () {
    test('should name the property list SMAppService looks for', () {
      final MacosServiceConfig macos = _parse(_macos).service!.macos!;

      expect(macos.plistFileName, 'com.example.demo.helper.plist');
      expect(macos.program, 'demo-helper');
    });

    test('should travel inside the bundle unless told otherwise', () {
      expect(_parse(_macos).service!.macos!.route, DarwinServiceRoute.bundled);
      expect(
        _parse('$_macos    route: system\n').service!.macos!.route,
        DarwinServiceRoute.system,
      );
    });

    test('should refuse a route nobody implements', () {
      expect(
        () => _parse('$_macos    route: pkg\n'),
        throwsA(
          isA<ConfigFailure>().having(
            (ConfigFailure f) => f.message,
            'message',
            contains('route'),
          ),
        ),
      );
    });
  });

  group('what it refuses, and why', () {
    test('a label outside the app namespace should be refused', () {
      // O launchd resolve o daemon por um nome que o sistema espera dentro do
      // namespace do aplicativo. Fora dele, registra e nunca casa — e o
      // sintoma é "não instalado" num daemon que existe.
      expect(
        () => _parse(
          'service:\n'
          '  macos:\n'
          '    label: com.outro.helper\n'
          '    program: demo-helper\n',
        ),
        throwsA(
          isA<ConfigFailure>().having(
            (ConfigFailure f) => f.message,
            'message',
            contains('namespace'),
          ),
        ),
      );
    });

    test('a path where a file name belongs should be refused', () {
      // O binário é copiado PARA DENTRO do bundle; o caminho onde ele foi
      // construído muda com a máquina.
      expect(
        () => _parse(
          'service:\n'
          '  macos:\n'
          '    label: com.example.demo.helper\n'
          '    program: target/debug/demo-helper\n',
        ),
        throwsA(
          isA<ConfigFailure>().having(
            (ConfigFailure f) => f.message,
            'message',
            contains('path'),
          ),
        ),
      );
    });

    test('a section that declares nothing should be refused', () {
      expect(
        () => _parse('service:\n  purge-paths: []\n'),
        throwsA(isA<ConfigFailure>()),
      );
    });
  });

  group('what it leaves alone', () {
    test('a linux-only project should keep its unit and gain no daemon', () {
      final ServiceConfig service = _parse(
        'service:\n'
        '  name: demo-helper.service\n'
        '  description: Privileged helper\n'
        '  exec-start: /usr/lib/demo/demo-helper\n',
      ).service!;

      expect(service.unit!.fileName, 'demo-helper.service');
      expect(service.macos, isNull);
    });

    test('a macos-only project should need no systemd unit', () {
      final ServiceConfig service = _parse(_macos).service!;

      expect(service.unit, isNull);
      expect(service.scripts, isNull);
      expect(service.macos, isNotNull);
    });

    test('an incomplete unit should still name the field it lacks', () {
      // Uma chave de Linux presente é um Linux incompleto, e não um projeto
      // que só quer macOS: o erro continua nomeando o campo que falta.
      expect(
        () => _parse(
          'service:\n'
          '  description: Privileged helper\n'
          '  exec-start: /usr/lib/demo/demo-helper\n',
        ),
        throwsA(
          isA<ConfigFailure>().having(
            (ConfigFailure f) => f.message,
            'message',
            contains('service.name'),
          ),
        ),
      );
    });
  });
}
