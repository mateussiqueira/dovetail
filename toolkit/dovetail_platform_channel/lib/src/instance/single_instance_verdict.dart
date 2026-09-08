enum SingleInstanceVerdict {
  primary,
  secondary,
  unavailable;

  bool get mayRun => this != SingleInstanceVerdict.secondary;

  bool get isGuarded => this != SingleInstanceVerdict.unavailable;
}
