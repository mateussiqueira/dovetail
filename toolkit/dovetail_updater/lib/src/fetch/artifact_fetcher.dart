import 'dart:typed_data';

typedef DownloadProgress = void Function(int received, int? total);

final class FetchedBody {
  const FetchedBody({required this.statusCode, required this.bytes});

  final int statusCode;
  final Uint8List bytes;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  bool get isNoContent => statusCode == 204;
}

abstract interface class ArtifactFetcher {
  Future<FetchedBody> fetch(Uri url, {DownloadProgress? onProgress});
}
