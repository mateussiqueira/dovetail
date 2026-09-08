import 'package:dovetail_bundler/dovetail_bundler.dart';

enum ArtifactKind {
  macosBundle('.app'),
  diskImage('.dmg'),
  debianPackage('.deb'),
  rpmPackage('.rpm'),
  windowsInstaller('.exe'),
  windowsPackage('.msi'),
  machO(''),
  unknown('');

  const ArtifactKind(this.extension);

  final String extension;
}

final class ArtifactInspection {
  const ArtifactInspection({
    required this.path,
    required this.kind,
    this.architectures = const <TargetArch>{},
    this.declaredArchitecture,
    this.signature,
    this.notes = const <String>[],
  });

  final String path;
  final ArtifactKind kind;
  final Set<TargetArch> architectures;
  final TargetArch? declaredArchitecture;
  final String? signature;
  final List<String> notes;

  bool get nameAgreesWithContent {
    if (declaredArchitecture == null || architectures.isEmpty) {
      return true;
    }
    return architectures.contains(declaredArchitecture);
  }

  List<String> get lines => <String>[
    'artefact  $path',
    'kind      ${kind.name}',
    if (architectures.isNotEmpty)
      'carries   ${architectures.map((TargetArch a) => a.apple).join(' + ')}',
    if (declaredArchitecture != null)
      'name says ${declaredArchitecture!.canonical}'
          '${nameAgreesWithContent ? '' : '   <-- DISAGREES WITH THE CONTENT'}',
    if (signature != null) 'signature $signature',
    ...notes.map((String note) => 'note      $note'),
  ];
}
