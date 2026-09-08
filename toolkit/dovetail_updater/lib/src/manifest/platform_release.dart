final class PlatformRelease {
  const PlatformRelease({required this.url, required this.signature});

  final String url;
  final String signature;

  @override
  bool operator ==(Object other) =>
      other is PlatformRelease &&
      other.url == url &&
      other.signature == signature;

  @override
  int get hashCode => Object.hash(url, signature);
}
