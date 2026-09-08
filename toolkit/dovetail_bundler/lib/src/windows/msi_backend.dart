import 'dart:io';

enum MsiBackend {
  wix('the WiX toolset', 'wix'),
  wixl('wixl, from msitools', 'wixl');

  const MsiBackend(this.label, this.executable);

  final String label;
  final String executable;

  static MsiBackend forHost({bool? onWindows}) =>
      (onWindows ?? Platform.isWindows) ? MsiBackend.wix : MsiBackend.wixl;

  bool get needsWindows => this == MsiBackend.wix;
}
