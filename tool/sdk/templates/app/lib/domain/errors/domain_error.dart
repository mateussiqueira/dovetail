class DomainError implements Exception {
  const DomainError(this.message);

  final String message;
}
