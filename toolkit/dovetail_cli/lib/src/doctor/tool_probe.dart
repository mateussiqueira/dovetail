enum ToolStatus { usable, unusable, absent, impostor }

final class ToolReport {
  const ToolReport({
    required this.name,
    required this.purpose,
    required this.status,
    this.path,
    this.detail,
  });

  final String name;
  final String purpose;
  final ToolStatus status;
  final String? path;
  final String? detail;

  bool get isUsable => status == ToolStatus.usable;

  String get line => switch (status) {
    ToolStatus.usable => 'ok       $name  ${path ?? ''}',
    ToolStatus.unusable =>
      'broken   $name  ${detail ?? 'present but refused a trivial input'}',
    ToolStatus.absent => 'missing  $name  ${detail ?? purpose}',
    ToolStatus.impostor =>
      'wrong    $name  ${detail ?? 'a different program answers to this name'}',
  };
}

abstract interface class ToolProbe {
  String get name;
  String get purpose;
  Future<ToolReport> probe();
}
