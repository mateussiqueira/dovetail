final class StagedFile {
  const StagedFile({required this.source, required this.destination});

  final String source;
  final String destination;

  @override
  bool operator ==(Object other) =>
      other is StagedFile &&
      other.source == source &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(source, destination);

  @override
  String toString() => 'StagedFile($source -> $destination)';
}
