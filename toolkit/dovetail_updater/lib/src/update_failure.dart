final class UpdateFailure implements Exception {
  const UpdateFailure(this.message, {this.remedy});

  final String message;
  final String? remedy;

  @override
  String toString() => remedy == null ? message : '$message\n  $remedy';
}
