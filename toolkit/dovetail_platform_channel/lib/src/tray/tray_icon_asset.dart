final class TrayIconAsset {
  const TrayIconAsset(this.path);

  final String path;

  @override
  bool operator ==(Object other) =>
      other is TrayIconAsset && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'TrayIconAsset($path)';
}
