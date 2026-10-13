enum DiskImageFormat {
  lzma('ULMO', <int>[10, 15]),
  zlib('UDZO', <int>[10, 0]);

  const DiskImageFormat(this.hdiutilName, this.oldestMacos);

  final String hdiutilName;
  final List<int> oldestMacos;

  String get oldestMacosName => oldestMacos.join('.');

  bool opensOn(String macos) {
    final List<int> parts = macos
        .split('.')
        .map((String part) => int.tryParse(part.trim()) ?? 0)
        .toList();
    for (int i = 0; i < oldestMacos.length; i++) {
      final int given = i < parts.length ? parts[i] : 0;
      if (given != oldestMacos[i]) {
        return given > oldestMacos[i];
      }
    }
    return true;
  }
}
