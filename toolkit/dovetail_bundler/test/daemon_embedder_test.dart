import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// O daemon dentro do bundle — o único lugar de onde ele chega numa máquina
/// pelo `.dmg`, que é o que esta ferramenta empacota no macOS.
bool get _hasPlistUtil =>
    Process.runSync('which', <String>['plutil']).exitCode == 0;

Directory _bundleFalso() {
  final Directory raiz = Directory.systemTemp.createTempSync('dovetail_daemon');
  Directory(
    p.join(raiz.path, 'Demo.app', 'Contents', 'MacOS'),
  ).createSync(recursive: true);
  return raiz;
}

File _binarioFalso(Directory raiz) {
  final File binario = File(p.join(raiz.path, 'demo-helper'))
    ..writeAsStringSync('#!/bin/sh\nexit 0\n');
  return binario;
}

void main() {
  group('o property list que ele escreve', () {
    test('should name the label and the file the same', () {
      // `SMAppService.daemon(plistName:)` resolve pelo NOME do arquivo e
      // compara com o rótulo lá dentro. Divergindo, registra e nunca casa.
      final String plist = DaemonEmbedder.plistFor(
        label: 'com.example.demo.helper',
        program: 'demo-helper',
      );

      expect(plist, contains('<string>com.example.demo.helper</string>'));
    });

    test('should point at the binary by a path relative to the bundle', () {
      // Absoluto aponta para a máquina que construiu, e o daemon não sobe na
      // máquina que instala.
      final String plist = DaemonEmbedder.plistFor(
        label: 'com.example.demo.helper',
        program: 'demo-helper',
      );

      expect(plist, contains('Contents/MacOS/demo-helper'));
      expect(plist, isNot(contains('/Users/')));
      expect(
        plist,
        contains(
          '<key>BundleProgram</key>\n'
          '    <string>Contents/MacOS/demo-helper</string>',
        ),
      );
      expect(
        plist,
        contains('<string>/var/log/com.example.demo.helper.log</string>'),
      );
    });

    test('should capture stdout and stderr at a path that needs no setup', () {
      // Um daemon que nao conecta nao deixa nada para ler se o launchd joga os
      // dois fluxos fora. `/var/log` existe em toda maquina: a rota `bundled`
      // nao tem postinstall para criar subdiretorio nenhum.
      final String plist = DaemonEmbedder.plistFor(
        label: 'com.example.demo.helper',
        program: 'demo-helper',
      );

      expect(plist, contains('<key>StandardOutPath</key>'));
      expect(plist, contains('<key>StandardErrorPath</key>'));
      expect(
        plist,
        contains('<string>/var/log/com.example.demo.helper.log</string>'),
      );
    });

    test('should carry the arguments the daemon is launched with', () {
      final String plist = DaemonEmbedder.plistFor(
        label: 'com.example.demo.helper',
        program: 'demo-helper',
        arguments: <String>['--service'],
      );

      expect(plist, contains('<string>--service</string>'));
    });

    test('should escape XML metacharacters in the label and in every '
        'argument', () {
      if (!_hasPlistUtil) {
        markTestSkipped('plutil is needed to parse the property list');
        return;
      }

      final String plist = DaemonEmbedder.plistFor(
        label: 'com.example.demo & <helpers>',
        program: 'demo-helper',
        arguments: <String>['--mode', 'a&b', '<strict>', 'x>y'],
      );

      // Os metacaracteres crus saem do yaml de quem usa o toolkit. Sem o
      // escape, cada um deles fechava um <string> antes da hora.
      expect(
        plist,
        contains('<string>com.example.demo &amp; &lt;helpers&gt;</string>'),
      );
      expect(plist, contains('<string>a&amp;b</string>'));
      expect(plist, contains('<string>&lt;strict&gt;</string>'));
      expect(plist, contains('<string>x&gt;y</string>'));

      // O plist gerado tem de ser XML válido: um malformado o launchd não
      // lê, e o sintoma é o registro que não acontece, na máquina de quem
      // usa, longe desta prova.
      final Directory scratch = Directory.systemTemp.createTempSync(
        'dovetail_plist',
      );
      addTearDown(() => scratch.deleteSync(recursive: true));
      final File written = File(
        p.join(scratch.path, 'com.example.demo.helper.plist'),
      )..writeAsStringSync(plist);
      final ProcessResult lint = Process.runSync('plutil', <String>[
        '-lint',
        written.path,
      ]);
      expect(
        lint.exitCode,
        0,
        reason:
            'um plist malformado não registra, e o launchd não diz por que\n'
            '${lint.stderr}',
      );

      // E o round-trip: o que o launchd lê de volta é o valor do yaml, não
      // a entidade.
      final ProcessResult decoded = Process.runSync('plutil', <String>[
        '-convert',
        'json',
        '-o',
        '-',
        written.path,
      ]);
      expect(decoded.exitCode, 0, reason: '${decoded.stderr}');
      expect(decoded.stdout, contains('a&b'));
      expect(decoded.stdout, contains('<strict>'));
      expect(decoded.stdout, contains('x>y'));
      expect(decoded.stdout, contains('com.example.demo & <helpers>'));
    });

    test('a program name carrying XML metacharacters should be refused, not '
        'escaped', () {
      // O nome vira arquivo em Contents/MacOS, chave relativa na assinatura
      // e entrada no plist; só a última decodifica entidades. Escapar uma e
      // não as outras obriga todo consumidor a decodificar para sempre.
      expect(
        () => DaemonEmbedder.plistFor(
          label: 'com.example.demo.helper',
          program: 'demo&helper',
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure f) => f.message,
            'message',
            contains('cannot carry'),
          ),
        ),
      );
    });

    test('should keep the daemon alive, because a dead one leaves the machine '
        'without network', () {
      final String plist = DaemonEmbedder.plistFor(
        label: 'com.example.demo.helper',
        program: 'demo-helper',
      );

      expect(plist, contains('<key>KeepAlive</key>'));
      expect(plist, contains('<key>RunAtLoad</key>'));
    });
  });

  group('o que ele deixa no bundle', () {
    test('should put the binary and the plist where macOS looks for them', () {
      final Directory raiz = _bundleFalso();
      addTearDown(() => raiz.deleteSync(recursive: true));
      final File binario = _binarioFalso(raiz);
      final String app = p.join(raiz.path, 'Demo.app');

      const DaemonEmbedder().embed(
        appDirectory: app,
        binary: binario.path,
        program: 'demo-helper',
        label: 'com.example.demo.helper',
        arguments: <String>['--service'],
      );

      expect(
        File(p.join(app, 'Contents', 'MacOS', 'demo-helper')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(
            app,
            'Contents',
            'Library',
            'LaunchDaemons',
            'com.example.demo.helper.plist',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test(
      'should leave the copy executable',
      () {
        // A cópia preserva conteúdo, não modo. O launchd recusa um daemon sem o
        // bit de execução com um erro que não diz isso.
        final Directory raiz = _bundleFalso();
        addTearDown(() => raiz.deleteSync(recursive: true));
        final File binario = _binarioFalso(raiz);
        final String app = p.join(raiz.path, 'Demo.app');

        const DaemonEmbedder().embed(
          appDirectory: app,
          binary: binario.path,
          program: 'demo-helper',
          label: 'com.example.demo.helper',
        );

        final ProcessResult modo = Process.runSync('test', <String>[
          '-x',
          p.join(app, 'Contents', 'MacOS', 'demo-helper'),
        ]);
        expect(modo.exitCode, 0);
      },
      skip: Platform.isWindows ? 'modo de arquivo é POSIX' : null,
    );

    test('should refuse to ship a bundle whose helper never arrived', () {
      final Directory raiz = _bundleFalso();
      addTearDown(() => raiz.deleteSync(recursive: true));

      expect(
        () => const DaemonEmbedder().embed(
          appDirectory: p.join(raiz.path, 'Demo.app'),
          binary: p.join(raiz.path, 'nao-existe'),
          program: 'demo-helper',
          label: 'com.example.demo.helper',
        ),
        throwsA(
          isA<BundleFailure>().having(
            (BundleFailure f) => f.message,
            'message',
            contains('not at'),
          ),
        ),
      );
    });
  });
}
