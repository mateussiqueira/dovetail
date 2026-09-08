final class ShipStep {
  const ShipStep({
    required this.label,
    required this.command,
    required this.arguments,
  });

  final String label;
  final String command;
  final List<String> arguments;

  List<String> get invocation => <String>[command, ...arguments];

  @override
  String toString() => invocation.join(' ');
}
