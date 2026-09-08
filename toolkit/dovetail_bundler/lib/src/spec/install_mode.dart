enum InstallMode {
  perMachine('admin', r'$PROGRAMFILES64', 'all'),
  currentUser('user', r'$LOCALAPPDATA', 'current');

  const InstallMode(this.executionLevel, this.defaultRoot, this.shellContext);

  final String executionLevel;
  final String defaultRoot;
  final String shellContext;
}
