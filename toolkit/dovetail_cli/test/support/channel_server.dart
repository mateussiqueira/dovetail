import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dovetail_cli/src/sdk/sdk_channel.dart';
import 'package:path/path.dart' as p;

/// O canal de release em miniatura: `latest`, o tarball de cada versão e o
/// `.sha256` dele, servidos por um HttpServer **TLS** de loopback — o
/// fetcher do updater só fala https, então o canal de teste fala a língua
/// do canal real. O certificado self-signed sai do openssl, como no teste
/// do próprio dovetail_updater.
///
/// O tarball é montado com o tar do sistema — o mesmo binário que instala —
/// para o formato do fixture não divergir do formato publicado. O
/// `bin/dovetail` de cada versão imprime a própria versão, para um teste
/// poder provar que o binário foi de fato trocado.
Future<HttpServer> serveSdkChannel({
  String? latest,
  required List<String> versions,
  Set<String> corruptShaFor = const <String>{},
}) async {
  final Directory certs = Directory.systemTemp.createTempSync('dt_certs');
  final String key = p.join(certs.path, 'key.pem');
  final String cert = p.join(certs.path, 'cert.pem');
  final ProcessResult made = Process.runSync('openssl', <String>[
    'req',
    '-x509',
    '-newkey',
    'rsa:2048',
    '-nodes',
    '-keyout',
    key,
    '-out',
    cert,
    '-days',
    '1',
    '-subj',
    '/CN=localhost',
  ]);
  if (made.exitCode != 0) {
    throw StateError(
      'openssl could not mint the loopback certificate: '
      '${made.stderr}',
    );
  }

  final SecurityContext context = SecurityContext()
    ..useCertificateChain(cert)
    ..usePrivateKey(key);

  final Map<String, List<int>> files = <String, List<int>>{
    if (latest != null) 'latest': utf8.encode('$latest\n'),
  };

  final Directory stage = Directory.systemTemp.createTempSync('dt_channel');
  for (final String version in versions) {
    final String name = SdkChannel.tarballName(version);
    final Directory layout = Directory(p.join(stage.path, version))
      ..createSync(recursive: true);
    final Directory bin = Directory(p.join(layout.path, 'bin'))
      ..createSync(recursive: true);
    File(
      p.join(bin.path, 'dovetail'),
    ).writeAsStringSync('#!/bin/sh\necho dovetail $version\n');
    for (final String package in <String>['dovetail', 'dovetail_rust_core']) {
      final Directory pkg = Directory(
        p.join(layout.path, 'sdk', version, 'packages', package),
      )..createSync(recursive: true);
      File(
        p.join(pkg.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: $package\nversion: $version\n');
    }

    final File tarball = File(p.join(stage.path, name));
    final ProcessResult packed = Process.runSync('tar', <String>[
      '-czf',
      tarball.path,
      '-C',
      layout.path,
      'bin',
      'sdk',
    ]);
    if (packed.exitCode != 0) {
      throw StateError(
        'tar could not build the channel fixture: '
        '${packed.stderr}',
      );
    }
    final List<int> bytes = tarball.readAsBytesSync();
    files['$version/$name'] = bytes;
    final String published = corruptShaFor.contains(version)
        ? '0' * 64
        : sha256.convert(bytes).toString();
    files['$version/$name.sha256'] = utf8.encode('$published\n');
  }

  final HttpServer server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  server.listen((HttpRequest request) {
    final String path = request.uri.path.substring(1);
    final List<int>? bytes = files[path];
    if (bytes == null) {
      request.response.statusCode = path == 'latest'
          ? HttpStatus.noContent
          : HttpStatus.notFound;
      request.response.close();
      return;
    }
    request.response.add(bytes);
    request.response.close();
  });

  return server;
}

/// A base do canal servido por [server].
String channelBase(HttpServer server) => 'https://127.0.0.1:${server.port}';

/// Um cliente que aceita o certificado self-signed do canal de loopback —
/// só para teste; o cliente de produção continua recusando o que não
/// confia.
HttpClient trustingClient() => HttpClient()
  ..badCertificateCallback = (X509Certificate cert, String host, int port) =>
      true;
