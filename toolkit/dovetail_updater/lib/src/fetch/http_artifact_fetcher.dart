import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_updater/src/fetch/artifact_fetcher.dart';
import 'package:dovetail_updater/src/update_failure.dart';

final class HttpArtifactFetcher implements ArtifactFetcher {
  HttpArtifactFetcher({
    HttpClient? client,
    this.maximumBytes = 512 * 1024 * 1024,
    this.timeout,
  }) : _client = client ?? HttpClient() {
    if (timeout != null) {
      _client.connectionTimeout = timeout;
    }
  }

  final HttpClient _client;
  final int maximumBytes;

  /// O máximo que se espera pela conexão, pelos cabeçalhos da resposta, e
  /// entre dois pedaços do corpo. Nulo espera o que o SO esperar — minutos,
  /// contra um host caído — o que é certo para um updater em segundo plano e
  /// errado para uma pessoa num terminal: `dovetail probe` contra um endpoint
  /// morto ficava mudo, sem dizer se estava pensando ou travado.
  final Duration? timeout;

  @override
  Future<FetchedBody> fetch(Uri url, {DownloadProgress? onProgress}) async {
    if (url.scheme != 'https') {
      throw UpdateFailure(
        'refusing to fetch $url over ${url.scheme}.',
        remedy: 'Only https carries an update.',
      );
    }

    try {
      return await _fetch(url, onProgress);
    } on TimeoutException {
      throw UpdateFailure(
        '$url did not answer within ${timeout!.inSeconds}s.',
        remedy:
            'Nothing arrived in that window — the host is down, filtered, or '
            'that slow. A shipped client would wait as long as the OS lets it.',
      );
    }
  }

  /// Quantos redirecionamentos se seguem antes de desistir. O mesmo padrao do
  /// `HttpClient`; um host que precisa de mais que isso esta em laco.
  static const int maximumRedirects = 5;

  Future<FetchedBody> _fetch(Uri url, DownloadProgress? onProgress) async {
    // Os saltos sao seguidos A MAO, e nao pelo `HttpClient`, porque o dele
    // segue de https para http sem dizer nada: um CDN mal configurado
    // respondendo 302 para um espelho http entregaria o manifesto em texto
    // claro com a cara de https, e a assinatura minisign cobre os bytes do
    // artefato, nao a versao nem a url que o manifesto anuncia. Seguir a mao
    // e o que permite RECUSAR antes de pedir: nada sai da maquina em claro.
    //
    // `Location` relativo e o caso comum num CDN (`Location: /path`), e ali o
    // Uri vem sem esquema — `resolveUri` contra a url atual e o que o
    // transforma no absoluto certo, herdando o https de quem redirecionou.
    // Comparar `hop.location.scheme` direto recusaria esse salto legitimo.
    Uri current = url;
    for (int hop = 0; ; hop++) {
      final HttpClientRequest request = await _bounded(_client.getUrl(current));
      request.followRedirects = false;
      // `*/*` junto, e nao so json: este mesmo metodo busca o manifesto E o
      // artefato, e pedir apenas `application/json` para um `.tar.gz` autoriza
      // um servidor rigoroso a responder 406. A preferencia pelo json fica —
      // e o que o endpoint do manifesto deve servir — sem excluir o resto.
      request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
      final HttpClientResponse response = await _bounded(request.close());

      if (!_isRedirect(response.statusCode)) {
        return _read(response, onProgress);
      }

      // Drenado AQUI, antes de qualquer recusa, e dentro do limite de tempo.
      //
      // O corpo de um 3xx nao interessa em nenhum caminho, e deixa-lo aberto
      // vaza o socket: medido, doze checagens recusadas deixaram doze conexoes
      // presas, alem do idleTimeout. E ele tem de ser limitado como o resto:
      // enquanto o `HttpClient` seguia os saltos, ele drenava o 3xx dentro do
      // `close()`, que este arquivo envolve em `_bounded` — seguir a mao sem
      // limitar o drain devolveu um jeito de o fetch pendurar para sempre,
      // com um 3xx que anuncia corpo e nao manda nenhum byte.
      await _bounded(response.drain<void>());

      final String? location = response.headers.value(
        HttpHeaders.locationHeader,
      );
      if (location == null || location.isEmpty) {
        throw UpdateFailure(
          '$current answered ${response.statusCode} with no Location.',
          remedy: 'A redirect without a destination is a broken endpoint.',
        );
      }
      if (hop >= maximumRedirects) {
        throw UpdateFailure(
          '$url redirected more than $maximumRedirects times.',
          remedy: 'An endpoint in a redirect loop serves nobody.',
        );
      }

      final Uri next = current.resolveUri(Uri.parse(location));
      if (next.scheme != 'https') {
        throw UpdateFailure(
          '$current redirected to $next, which is not https.',
          remedy:
              'An update endpoint has to stay on https end to end. A redirect '
              'to a cleartext mirror lets anyone on the path rewrite the '
              'manifest, and the signature only covers the artefact bytes. '
              'Nothing was fetched over the cleartext hop.',
        );
      }
      current = next;
    }
  }

  static bool _isRedirect(int status) =>
      status == HttpStatus.movedPermanently ||
      status == HttpStatus.found ||
      status == HttpStatus.seeOther ||
      status == HttpStatus.temporaryRedirect ||
      status == HttpStatus.permanentRedirect;

  Future<FetchedBody> _read(
    HttpClientResponse response,
    DownloadProgress? onProgress,
  ) async {
    if (response.statusCode == 204) {
      return FetchedBody(statusCode: 204, bytes: Uint8List(0));
    }

    final int? total = response.contentLength >= 0
        ? response.contentLength
        : null;
    if (total != null && total > maximumBytes) {
      // Descartada, nao drenada: drenar aqui seria baixar exatamente os bytes
      // que o teto recusa. Sem descartar, o corpo nunca lido deixa a conexao
      // presa — medido: seis recusas, seis conexoes que o servidor ainda ve
      // abertas. (O teto de meio de fluxo nao precisa disto: sair do
      // `await for` com excecao cancela a subscription, e ali o mesmo teste
      // conta UMA conexao para seis recusas.)
      await _discard(response);
      throw UpdateFailure(
        'the artefact declares $total bytes, over the $maximumBytes ceiling.',
      );
    }

    final BytesBuilder collected = BytesBuilder(copy: false);
    await for (final List<int> chunk in _boundedStream(response)) {
      collected.add(chunk);
      if (collected.length > maximumBytes) {
        throw UpdateFailure(
          'the download passed the $maximumBytes ceiling mid stream.',
          remedy: 'Nothing was written to disk.',
        );
      }
      onProgress?.call(collected.length, total);
    }

    return FetchedBody(
      statusCode: response.statusCode,
      bytes: collected.toBytes(),
    );
  }

  /// Fecha a conexao sem ler o corpo. Se o socket ja se foi, nao ha o que
  /// destruir — e isso nao e erro do lado de quem recusou.
  static Future<void> _discard(HttpClientResponse response) async {
    try {
      (await response.detachSocket()).destroy();
    } on Object catch (_) {
      return;
    }
  }

  Future<T> _bounded<T>(Future<T> future) =>
      timeout == null ? future : future.timeout(timeout!);

  /// Um limite entre pedaços, não sobre o download inteiro: um artefato de
  /// 200 MB num link lento não tem prazo total razoável, mas um corpo que para
  /// de chegar por [timeout] é um corpo que parou.
  Stream<List<int>> _boundedStream(Stream<List<int>> body) =>
      timeout == null ? body : body.timeout(timeout!);

  void close() => _client.close(force: true);
}
