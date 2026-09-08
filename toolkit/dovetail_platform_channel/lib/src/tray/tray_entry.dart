sealed class TrayEntry {
  const TrayEntry();
}

final class TrayCommand extends TrayEntry {
  const TrayCommand({
    required this.id,
    required this.label,
    this.enabled = true,
    this.checked,
  });

  final String id;
  final String label;
  final bool enabled;
  final bool? checked;
}

final class TraySeparator extends TrayEntry {
  const TraySeparator();
}

final class TraySubmenu extends TrayEntry {
  const TraySubmenu({required this.label, required this.entries});

  final String label;
  final List<TrayEntry> entries;
}
