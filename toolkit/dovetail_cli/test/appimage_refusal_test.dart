import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Um AppImage não instala nada: ele executa de um arquivo. Sem instalar não há
/// unit systemd, sem a unit não há helper privilegiado, e sem o helper não há
/// kill switch — o que sai não é produto degradado, é uma janela que não
/// conecta, num formato que parecia ter sido construído com sucesso.
///
/// O README já dizia isso em prosa, e o ramo do AppImage no `bundle` passava
/// direto: `unit`, `policy` e `scripts` chegam ao deb e ao rpm e não chegavam
/// ali, então o serviço sumia em silêncio. Dizer em prosa não impede ninguém.
void main() {
  late Directory root;
  late CommandRunner<int> runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_appimage');
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(BundleCommand());
  });

  tearDown(() => root.deleteSync(recursive: true));

  void writeConfig({required bool withService}) {
    File(p.join(root.path, 'dovetail.yaml')).writeAsStringSync('''
identifier: com.example.app
name: Exemplo
manufacturer: Example Org
targets: [linux-x86_64]
${withService ? '''
service:
  name: exemplo-helper.service
  description: O helper privilegiado do Exemplo
  exec-start: /usr/lib/exemplo/exemplo-helper
''' : ''}''');
  }

  String appDirectory() {
    final Directory bundle = Directory(p.join(root.path, 'bundle'))
      ..createSync();
    File(p.join(bundle.path, 'exemplo')).writeAsStringSync('binary');
    return bundle.path;
  }

  List<String> argumentsFor(String format) => <String>[
    'bundle',
    '--target',
    'linux',
    '--arch',
    'x86_64',
    '--root',
    root.path,
    '--product-name',
    'Exemplo',
    '--manufacturer',
    'Example Org',
    '--identifier',
    'com.example.app',
    '--version',
    '1.0.0',
    '--main-binary',
    'exemplo',
    '--app-dir',
    appDirectory(),
    '--out-dir',
    p.join(root.path, 'dist'),
    '--linux-format',
    format,
  ];

  test(
    'a service plus appimage should be refused, not built quietly',
    () async {
      writeConfig(withService: true);

      await expectLater(
        runner.run(argumentsFor('appimage')),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('cannot install one'),
          ),
        ),
      );
    },
  );

  test(
    'the refusal should name the unit, so the reader sees what is lost',
    () async {
      writeConfig(withService: true);

      await expectLater(
        runner.run(argumentsFor('appimage')),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('exemplo-helper.service'),
          ),
        ),
      );
    },
  );

  test('the remedy should point at the formats that do install', () async {
    writeConfig(withService: true);

    await expectLater(
      runner.run(argumentsFor('appimage')),
      throwsA(
        isA<UsageException>().having(
          (UsageException error) => error.usage,
          'usage',
          allOf(
            contains('--linux-format both'),
            contains('polkit'),
            // As três rotas para privilégio estão fechadas, não difíceis, e a
            // recusa diz quais — senão a resposta é "então conserta".
            contains('nosuid'),
          ),
        ),
      ),
    );
  });

  test(
    'no service means no refusal: the framework is not this product',
    () async {
      writeConfig(withService: false);

      // Chega ao bundler de verdade, que então recusa por outro motivo — não
      // existe runtime type2 nesta máquina. O ponto é que a recusa mudou de
      // dona: passou do guarda de configuração para a ferramenta que falta.
      await expectLater(
        runner.run(argumentsFor('appimage')),
        throwsA(
          isA<Object>().having(
            (Object error) => '$error',
            'mensagem',
            isNot(contains('cannot install one')),
          ),
        ),
      );
    },
  );

  test(
    'deb should build with the very service appimage was refused for',
    () async {
      writeConfig(withService: true);

      // O deb instala a unit pelo postinst, então o serviço declarado é
      // exatamente o que ele sabe carregar. É por isso que a recusa do AppImage
      // é sobre o formato e não sobre o serviço: mesma config, mesmo comando,
      // resultado oposto.
      expect(await runner.run(argumentsFor('deb')), 0);
      expect(
        Directory(
          p.join(root.path, 'dist'),
        ).listSync().map((FileSystemEntity each) => p.basename(each.path)),
        contains('exemplo_1.0.0_amd64.deb'),
      );
    },
  );
}
