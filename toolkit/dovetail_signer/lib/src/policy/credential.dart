final class Credential {
  const Credential({required this.name, required this.purpose});

  final String name;
  final String purpose;

  @override
  bool operator ==(Object other) => other is Credential && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

final class CredentialGroup {
  const CredentialGroup({required this.label, required this.members});

  final String label;
  final List<Credential> members;

  bool isSatisfiedBy(Map<String, String> environment) =>
      members.every((Credential credential) {
        final String? value = environment[credential.name];
        return value != null && value.trim().isNotEmpty;
      });

  bool isPartiallySatisfiedBy(Map<String, String> environment) =>
      !isSatisfiedBy(environment) &&
      members.any((Credential credential) {
        final String? value = environment[credential.name];
        return value != null && value.trim().isNotEmpty;
      });

  List<Credential> missingIn(Map<String, String> environment) =>
      members.where((Credential credential) {
        final String? value = environment[credential.name];
        return value == null || value.trim().isEmpty;
      }).toList();
}
