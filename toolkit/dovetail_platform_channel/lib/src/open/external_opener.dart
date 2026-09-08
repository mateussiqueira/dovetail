abstract interface class ExternalOpener {
  Future<bool> openUrl(Uri url);
  Future<bool> canOpenUrl(Uri url);
}
