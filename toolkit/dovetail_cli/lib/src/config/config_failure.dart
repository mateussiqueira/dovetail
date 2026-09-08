final class ConfigFailure implements Exception {
  const ConfigFailure(this.message, {this.remedy, this.origin});

  final String message;
  final String? remedy;
  final String? origin;

  @override
  String toString() {
    final String where = origin == null ? '' : ' ($origin)';
    final String how = remedy == null ? '' : '\n  $remedy';
    return 'config$where: $message$how';
  }
}
