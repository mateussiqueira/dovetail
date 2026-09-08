import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _Loopback {
  _Loopback._(this.server, this.root);

  final HttpServer server;
  final Directory root;

  static Future<_Loopback?> start(
    Future<void> Function(HttpRequest request) handle,
  ) async {
    if (Process.runSync('which', <String>['openssl']).exitCode != 0) {
      return null;
    }

    final Directory root = Directory.systemTemp.createTempSync('fetcher_tls');
    final String key = p.join(root.path, 'key.pem');
    final String certificate = p.join(root.path, 'cert.pem');

    final ProcessResult made = Process.runSync('openssl', <String>[
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-keyout',
      key,
      '-out',
      certificate,
      '-days',
      '1',
      '-nodes',
      '-subj',
      '/CN=localhost',
      '-addext',
      'subjectAltName=DNS:localhost,IP:127.0.0.1',
    ]);
    if (made.exitCode != 0) {
      root.deleteSync(recursive: true);
      return null;
    }

    final SecurityContext context = SecurityContext()
      ..useCertificateChain(certificate)
      ..usePrivateKey(key);

    final HttpServer server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    server.listen((HttpRequest request) async {
      await handle(request);
      await request.response.close();
    });

    return _Loopback._(server, root);
  }

  Uri get url => Uri.parse('https://localhost:${server.port}/artifact');

  Future<void> stop() async {
    await server.close(force: true);
    root.deleteSync(recursive: true);
  }
}

HttpClient _trustingClient() =>
    HttpClient()
      ..badCertificateCallback = (X509Certificate _, String _, int _) => true;

void main() {
  group('HttpArtifactFetcher without a server', () {
    test('should refuse anything that is not https', () async {
      for (final String scheme in <String>['http', 'ftp', 'file']) {
        await expectLater(
          HttpArtifactFetcher().fetch(Uri.parse('$scheme://cdn/app.tar.gz')),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.remedy,
              'remedy',
              contains('Only https'),
            ),
          ),
          reason: scheme,
        );
      }
    });
  });

  group('HttpArtifactFetcher against a loopback server', () {
    late _Loopback? server;

    tearDown(() async => server?.stop());

    Future<bool> serving(
      Future<void> Function(HttpRequest request) handle,
    ) async {
      server = await _Loopback.start(handle);
      return server != null;
    }

    test('should carry the body and the status back', () async {
      if (!await serving((HttpRequest request) async {
        request.response.add(utf8.encode('the artefact bytes'));
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      final FetchedBody body = await HttpArtifactFetcher(
        client: _trustingClient(),
      ).fetch(server!.url);

      expect(body.statusCode, 200);
      expect(utf8.decode(body.bytes), 'the artefact bytes');
    });

    test('a 204 should come back empty, not as a failure', () async {
      if (!await serving((HttpRequest request) async {
        request.response.statusCode = 204;
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      final FetchedBody body = await HttpArtifactFetcher(
        client: _trustingClient(),
      ).fetch(server!.url);

      expect(body.statusCode, 204);
      expect(body.bytes, isEmpty);
    });

    test('a declared size over the ceiling should not leave the connection '
        'behind', () async {
      // Recusar sem ler o corpo deixava a conexao presa: medido, seis recusas
      // deixavam seis conexoes que o servidor ainda via abertas. Drenar aqui
      // seria baixar justamente os bytes que o teto recusa, entao a conexao e
      // DESCARTADA. (O teto de meio de fluxo nao tem esse problema: sair do
      // `await for` com excecao cancela a subscription.)
      if (!await serving((HttpRequest request) async {
        request.response.contentLength = 4096;
        request.response.add(Uint8List(4096));
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      final HttpArtifactFetcher fetcher = HttpArtifactFetcher(
        client: _trustingClient(),
        maximumBytes: 1024,
      );
      for (int attempt = 0; attempt < 3; attempt++) {
        await expectLater(
          fetcher.fetch(server!.url),
          throwsA(isA<UpdateFailure>()),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final HttpConnectionsInfo open = server!.server.connectionsInfo();
      expect(
        open.total,
        0,
        reason:
            'tres recusas deixaram ${open.total} conexoes abertas; num app que '
            'checa a cada seis horas, e um descritor por checagem',
      );
    });

    test(
      'a declared size over the ceiling should be refused before the body',
      () async {
        if (!await serving((HttpRequest request) async {
          request.response.contentLength = 4096;
          request.response.add(Uint8List(4096));
        })) {
          markTestSkipped('openssl is needed to serve https on loopback');
          return;
        }

        await expectLater(
          HttpArtifactFetcher(
            client: _trustingClient(),
            maximumBytes: 1024,
          ).fetch(server!.url),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.message,
              'message',
              contains('declares'),
            ),
          ),
        );
      },
    );

    test(
      'a body that passes the ceiling mid stream should be refused',
      () async {
        if (!await serving((HttpRequest request) async {
          for (int i = 0; i < 8; i++) {
            request.response.add(Uint8List(1024));
            await request.response.flush();
          }
        })) {
          markTestSkipped('openssl is needed to serve https on loopback');
          return;
        }

        await expectLater(
          HttpArtifactFetcher(
            client: _trustingClient(),
            maximumBytes: 2048,
          ).fetch(server!.url),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.remedy,
              'remedy',
              contains('Nothing was written to disk'),
            ),
          ),
          reason:
              'a server that never declares a length can still hand over more '
              'than the machine should hold',
        );
      },
    );

    test('the Accept header should prefer json without excluding the '
        'artefact', () async {
      // O mesmo metodo busca o manifesto e o `.tar.gz`. Pedir so
      // `application/json` autoriza um servidor rigoroso a responder 406 no
      // download — e o download e o passo que ninguem quer perder.
      String? accepted;
      if (!await serving((HttpRequest request) async {
        accepted = request.headers.value(HttpHeaders.acceptHeader);
        request.response.add(utf8.encode('bytes'));
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      await HttpArtifactFetcher(client: _trustingClient()).fetch(server!.url);

      expect(accepted, contains('application/json'));
      expect(accepted, contains('*/*'));
    });

    test('a redirect that leaves https should be refused, even when the '
        'destination answers', () async {
      // Um servidor http simples como destino: se o fetcher seguisse, leria o
      // manifesto em texto claro com a cara de https.
      final HttpServer plain = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      plain.listen((HttpRequest request) async {
        request.response.write('PLAINTEXT over http');
        await request.response.close();
      });
      if (!await serving((HttpRequest request) async {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${plain.port}/x',
        );
      })) {
        await plain.close(force: true);
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      try {
        await expectLater(
          HttpArtifactFetcher(client: _trustingClient()).fetch(server!.url),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.message,
              'message',
              contains('not https'),
            ),
          ),
        );
      } finally {
        await plain.close(force: true);
      }
    });

    test('a RELATIVE Location should be followed, inheriting the https it '
        'came from', () async {
      // `Location: /real` e a forma comum num CDN, e ali o Uri vem sem
      // esquema. Comparar o esquema do Location direto recusaria este salto —
      // e quebraria o updater contra qualquer host normal.
      if (!await serving((HttpRequest request) async {
        if (request.uri.path == '/artifact') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '/real');
          return;
        }
        request.response.add(utf8.encode('relative hop followed'));
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      final FetchedBody body = await HttpArtifactFetcher(
        client: _trustingClient(),
      ).fetch(server!.url);

      expect(utf8.decode(body.bytes), 'relative hop followed');
    });

    test('a 3xx that announces a body and sends none should fail at the '
        'limit, not hang', () async {
      // Enquanto o HttpClient seguia os saltos, ele drenava o corpo do 3xx
      // dentro do `close()`, que esta classe limita. Seguir a mao sem limitar
      // o drain devolveu um jeito de o fetch pendurar para sempre.
      if (!await serving((HttpRequest request) async {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/real');
        request.response.headers.contentLength = 16;
        await Completer<void>().future;
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      final Stopwatch clock = Stopwatch()..start();
      await expectLater(
        HttpArtifactFetcher(
          client: _trustingClient(),
          timeout: const Duration(milliseconds: 500),
        ).fetch(server!.url),
        throwsA(isA<UpdateFailure>()),
      );
      expect(
        clock.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason:
            'o limite era meio segundo, e o drain do 3xx tem de respeita-lo',
      );
    });

    test('a redirect loop should stop at the limit, not spin', () async {
      if (!await serving((HttpRequest request) async {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/again');
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      await expectLater(
        HttpArtifactFetcher(client: _trustingClient()).fetch(server!.url),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('more than'),
          ),
        ),
      );
    });

    test(
      'a 3xx with no Location should be refused, not read as a body',
      () async {
        if (!await serving((HttpRequest request) async {
          request.response.statusCode = HttpStatus.found;
        })) {
          markTestSkipped('openssl is needed to serve https on loopback');
          return;
        }

        await expectLater(
          HttpArtifactFetcher(client: _trustingClient()).fetch(server!.url),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.message,
              'message',
              contains('no Location'),
            ),
          ),
        );
      },
    );

    test('a redirect that stays on https should be followed', () async {
      if (!await serving((HttpRequest request) async {
        if (request.uri.path == '/artifact') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'https://localhost:${server!.server.port}/real',
          );
          return;
        }
        request.response.add(utf8.encode('followed'));
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      final FetchedBody body = await HttpArtifactFetcher(
        client: _trustingClient(),
      ).fetch(server!.url);

      expect(utf8.decode(body.bytes), 'followed');
    });

    test(
      'a server that never answers should fail at the limit, not hang',
      () async {
        if (!await serving((HttpRequest request) async {
          // Nunca responde: nem cabecalho, nem corpo. Sem limite, o cliente
          // espera o que o SO esperar — e `dovetail probe` ficava mudo.
          await Completer<void>().future;
        })) {
          markTestSkipped('openssl is needed to serve https on loopback');
          return;
        }

        final Stopwatch clock = Stopwatch()..start();
        await expectLater(
          HttpArtifactFetcher(
            client: _trustingClient(),
            timeout: const Duration(milliseconds: 500),
          ).fetch(server!.url),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.message,
              'message',
              contains('did not answer within 0s'),
            ),
          ),
        );
        expect(
          clock.elapsed,
          lessThan(const Duration(seconds: 5)),
          reason: 'o limite era meio segundo; isto e o teste de que ele vale',
        );
      },
    );

    test(
      'a body that stalls mid stream should fail at the limit too',
      () async {
        if (!await serving((HttpRequest request) async {
          request.response.add(Uint8List(1024));
          await request.response.flush();
          await Completer<void>().future;
        })) {
          markTestSkipped('openssl is needed to serve https on loopback');
          return;
        }

        await expectLater(
          HttpArtifactFetcher(
            client: _trustingClient(),
            timeout: const Duration(milliseconds: 500),
          ).fetch(server!.url),
          throwsA(isA<UpdateFailure>()),
          reason:
              'o limite e entre pedacos: um corpo que parou de chegar e um '
              'corpo que parou, por mais que os cabecalhos tenham vindo',
        );
      },
    );

    test('a limit the server beats should change nothing', () async {
      if (!await serving((HttpRequest request) async {
        request.response.add(utf8.encode('quick'));
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      final FetchedBody body = await HttpArtifactFetcher(
        client: _trustingClient(),
        timeout: const Duration(seconds: 10),
      ).fetch(server!.url);

      expect(utf8.decode(body.bytes), 'quick');
    });

    test(
      'an undeclared length should report progress with a null total',
      () async {
        if (!await serving((HttpRequest request) async {
          for (int i = 0; i < 3; i++) {
            request.response.add(Uint8List(512));
            await request.response.flush();
          }
        })) {
          markTestSkipped('openssl is needed to serve https on loopback');
          return;
        }

        final List<int?> totals = <int?>[];
        final List<int> received = <int>[];
        await HttpArtifactFetcher(client: _trustingClient()).fetch(
          server!.url,
          onProgress: (int soFar, int? total) {
            received.add(soFar);
            totals.add(total);
          },
        );

        expect(received, isNotEmpty);
        expect(received.last, 1536);
        expect(
          totals.every((int? total) => total == null),
          true,
          reason:
              'contentLength is -1 when the server streams, and a negative total '
              'must not be reported as a size',
        );
      },
    );

    test('progress should be monotonic and end at the body size', () async {
      if (!await serving((HttpRequest request) async {
        request.response.contentLength = 3072;
        for (int i = 0; i < 3; i++) {
          request.response.add(Uint8List(1024));
          await request.response.flush();
        }
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      final List<int> received = <int>[];
      final FetchedBody body =
          await HttpArtifactFetcher(client: _trustingClient()).fetch(
            server!.url,
            onProgress: (int soFar, int? _) => received.add(soFar),
          );

      expect(body.bytes, hasLength(3072));
      expect(received.last, 3072);
      for (int i = 1; i < received.length; i++) {
        expect(received[i], greaterThan(received[i - 1]));
      }
    });

    test(
      'a server error should come back as its status, not as a throw',
      () async {
        if (!await serving((HttpRequest request) async {
          request.response.statusCode = 503;
        })) {
          markTestSkipped('openssl is needed to serve https on loopback');
          return;
        }

        final FetchedBody body = await HttpArtifactFetcher(
          client: _trustingClient(),
        ).fetch(server!.url);

        expect(
          body.statusCode,
          503,
          reason:
              'the caller decides what an outage means; the fetcher reports what '
              'the server said',
        );
      },
    );

    test('close should end the client it was given', () async {
      if (!await serving((HttpRequest request) async {
        request.response.add(utf8.encode('x'));
      })) {
        markTestSkipped('openssl is needed to serve https on loopback');
        return;
      }

      final HttpArtifactFetcher fetcher = HttpArtifactFetcher(
        client: _trustingClient(),
      );
      await fetcher.fetch(server!.url);
      fetcher.close();

      await expectLater(fetcher.fetch(server!.url), throwsA(anything));
    });
  });
}
