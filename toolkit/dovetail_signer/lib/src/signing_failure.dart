final class SigningFailure implements Exception {
  const SigningFailure(this.message, {this.remedy});

  final String message;
  final String? remedy;

  @override
  String toString() => remedy == null ? message : '$message\n  $remedy';
}
