import 'dart:io';

import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// O daemon dentro do bundle — o único lugar de onde ele chega numa máquina
/// pelo `.dmg`, que é o que esta ferramenta empacota no macOS.
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
      expect(plist, isNot(contains('<string>/')));
    });

    test('should carry the arguments the daemon is launched with', () {
      final String plist = DaemonEmbedder.plistFor(
        label: 'com.example.demo.helper',
        program: 'demo-helper',
        arguments: <String>['--service'],
      );

      expect(plist, contains('<string>--service</string>'));
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
