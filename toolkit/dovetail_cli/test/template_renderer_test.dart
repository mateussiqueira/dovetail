import 'dart:io';

import 'package:dovetail_cli/src/scaffold/template_renderer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

void main() {
  late Directory from;
  late Directory to;

  setUp(() {
    from = Directory.systemTemp.createTempSync('dovetail_template_from');
    to = Directory.systemTemp.createTempSync('dovetail_template_to');
  });

  tearDown(() {
    from.deleteSync(recursive: true);
    to.deleteSync(recursive: true);
  });

  test('a .template file is written under the name without the suffix', () {
    File(
      p.join(from.path, 'Cargo.toml.template'),
    ).writeAsStringSync('[package]\nname = "{{name}}_core"\n');

    TemplateRenderer.renderTree(
      from: from,
      to: to,
      values: <String, String>{'name': 'demo'},
    );

    expect(
      File(p.join(to.path, 'Cargo.toml')).readAsStringSync(),
      contains('name = "demo_core"'),
    );
    expect(
      File(p.join(to.path, 'Cargo.toml.template')).existsSync(),
      isFalse,
      reason: 'o sufixo nao pode sobrar no projeto gerado',
    );
  });

  test('a file without the suffix keeps its name', () {
    File(
      p.join(from.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: {{name}}\n');

    TemplateRenderer.renderTree(
      from: from,
      to: to,
      values: <String, String>{'name': 'demo'},
    );

    expect(
      File(p.join(to.path, 'pubspec.yaml')).readAsStringSync(),
      'name: demo\n',
    );
  });

  // O cargo resolve uma dependencia por git varrendo TODO manifesto do
  // repositorio — `workspace.exclude` nao impede a varredura —, e um arquivo
  // chamado `Cargo.toml` que carrega `{{name}}` e erro de parse para ele. O
  // erro aparece no consumidor, apontando para um template que ele nunca pediu.
  // Enquanto um template se chamar `Cargo.toml`, isso volta.
  test('no template ships a file literally named Cargo.toml', () {
    for (final String tree in <String>['app', 'bridge']) {
      final Directory root = Directory(
        inRepo(<String>['tool', 'sdk', 'templates', tree]),
      );
      final List<String> manifests =
          root
              .listSync(recursive: true)
              .whereType<File>()
              .map((File file) => file.path)
              .where((String path) => p.basename(path) == 'Cargo.toml')
              .toList()
            ..sort();

      expect(
        manifests,
        isEmpty,
        reason:
            'o cargo le o repositorio inteiro ao resolver a dependencia git, '
            'e um Cargo.toml de template vira erro de parse no consumidor: '
            '$manifests',
      );
    }
  });
}
