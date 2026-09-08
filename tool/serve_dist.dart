// Serve um diretório (o `dist/` de um release) por https em loopback, para
// exercitar o `probe` e o updater do app contra um host de verdade — sem o
// host de verdade. Só `dart:io`, como os outros scripts de tool/.
//
//   dart tool/serve_dist.dart --root product/vpn_desktop/dist \
//     --cert tls/srv.crt --key tls/srv.key [--port 8443]
//
// https e obrigatório de propósito: o fetcher, o `probe`, o `ManifestWriter`
// e o `UpdateConfig` recusam http em quatro camadas, e um servidor local que
// falasse http provaria um caminho que o cliente nunca percorre. O
// certificado sai de tool/ci/prove_update.sh (CA privada + folha para
// localhost); o cliente confia nela com `probe --ca <ca.crt>`, que ADICIONA
// uma raiz e mantém a verificação de cadeia e de hostname.
//
// Uma única conveniência, anunciada no log: `GET /desktop-version/check/<os>`
// devolve `<root>/latest.json` — é a forma do endpoint que o app instalado
// consulta (`.../check/{{target}}`), e um servidor que só respondesse
// `/latest.json` não serviria ao app.
//
// Fora disso ele é burro de propósito: serve o arquivo que existe no caminho
// pedido, e 404 no resto. Houve um atalho aqui — qualquer
// `/<a>/<versão>/<arquivo>` caía para `<root>/<arquivo>` — porque o `release`
// escreve o `dist/` plano e o manifesto aponta para
// `<base-url>/<versão>/<arquivo>`. Só que assim o caminho da URL nunca era
// exercitado: uma versão errada no manifesto seria servida igual, e num host
// real daria 404. Quem monta o layout é `tool/ci/prove_update.sh`.
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final Map<String, String> options = _parse(arguments);
  final String? root = options['root'];
  final String? cert = options['cert'];
  final String? key = options['key'];
  if (root == null || cert == null || key == null) {
    stderr.writeln(
      'usage: dart tool/serve_dist.dart --root <dir> --cert <pem> --key <pem> '
      '[--port 8443]',
    );
    exit(64);
  }
  for (final MapEntry<String, String> path in <String, String>{
    '--root': root,
    '--cert': cert,
    '--key': key,
  }.entries) {
    if (!File(path.value).existsSync() && !Directory(path.value).existsSync()) {
      stderr.writeln('${path.key} ${path.value} does not exist');
      exit(64);
    }
  }
  final int port = int.tryParse(options['port'] ?? '8443') ?? 8443;

  final SecurityContext context = SecurityContext()
    ..useCertificateChain(cert)
    ..usePrivateKey(key);
  final HttpServer server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    port,
    context,
  );
  stdout.writeln(
    'serving $root at https://localhost:${server.port} (loopback only)',
  );
  stdout.writeln('  /desktop-version/check/<os> -> latest.json');
  stdout.writeln('  everything else               -> the file at that path');

  await for (final HttpRequest request in server) {
    final String path = request.uri.path;
    final File? file = _resolve(root, path);
    if (file == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      stdout.writeln('404 ${request.method} $path');
      continue;
    }
    request.response.headers.contentType =
        path.endsWith('.json') || file.path.endsWith('.json')
        ? ContentType.json
        : ContentType.binary;
    final int length = file.lengthSync();
    request.response.contentLength = length;
    await request.response.addStream(file.openRead());
    await request.response.close();
    stdout.writeln(
      '200 ${request.method} $path -> ${file.path} ($length bytes)',
    );
  }
}

File? _resolve(String root, String path) {
  final List<String> segments = path
      .split('/')
      .where((String s) => s.isNotEmpty)
      .toList();
  if (segments.isEmpty) {
    return null;
  }
  // Traversal fora do root e recusado; e um servidor de prova, nao um CDN.
  if (segments.any((String s) => s == '..')) {
    return null;
  }

  if (segments.length == 3 &&
      segments[0] == 'desktop-version' &&
      segments[1] == 'check') {
    final File manifest = File('$root/latest.json');
    return manifest.existsSync() ? manifest : null;
  }

  final File exact = File('$root/${segments.join('/')}');
  return exact.existsSync() ? exact : null;
}

Map<String, String> _parse(List<String> arguments) {
  final Map<String, String> options = <String, String>{};
  for (int i = 0; i < arguments.length; i++) {
    final String argument = arguments[i];
    if (!argument.startsWith('--')) {
      continue;
    }
    final int equals = argument.indexOf('=');
    if (equals > 0) {
      options[argument.substring(2, equals)] = argument.substring(equals + 1);
    } else if (i + 1 < arguments.length) {
      options[argument.substring(2)] = arguments[++i];
    }
  }
  return options;
}
