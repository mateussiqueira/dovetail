final class BundleFailure implements Exception {
  const BundleFailure(this.message, {this.remedy});

  final String message;
  final String? remedy;

  @override
  String toString() => remedy == null ? message : '$message\n  $remedy';
}
