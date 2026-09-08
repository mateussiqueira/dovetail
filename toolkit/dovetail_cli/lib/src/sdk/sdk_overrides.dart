import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;

/// O `pubspec_overrides.yaml` que aponta o runtime para o SDK instalado — o
/// mesmo mecanismo que o Flutter SDK usa para entregar os pacotes dele. Um
/// formato, dois emissores (`init --sdk` e `new --sdk`), para nunca
/// discordarem.
final class SdkOverrides {
  const SdkOverrides._();

  static const String fileName = 'pubspec_overrides.yaml';

  /// Localiza o SDK com [locator], ou recusa nomeando o instalador.
  static SdkInstall requireSdk(SdkLocator locator, String usage) {
    final SdkInstall? sdk = locator.locate();
    if (sdk == null) {
      throw UsageException(
        'no dovetail SDK installed at ${locator.home}/sdk.',
        'The runtime resolves from the installed SDK, and there is nothing '
            'there to point $fileName at. Install one first:\n'
            '  curl -fsSL "\$DOVETAIL_INSTALL_URL"/install.sh | sh\n\n$usage',
      );
    }
    return sdk;
  }

  /// O YAML, cada pacote do runtime apontando para [sdk]. Os caminhos são
  /// locais, então o arquivo não é para versionar.
  static String render(SdkInstall sdk) {
    final List<String> packages = sdk.packages();
    if (packages.isEmpty) {
      throw UsageException(
        'the dovetail SDK at ${sdk.packagesDir} carries no packages.',
        'A directory with no pubspec.yaml is not a package, and an override '
            'to nothing is a pub get that fails. Reinstall the SDK.',
      );
    }

    final StringBuffer out = StringBuffer(
      '# Written by dovetail. Do not version: paths are local.\n'
      'dependency_overrides:\n',
    );
    for (final String package in packages) {
      out
        ..writeln('  $package:')
        ..writeln('    path: ${_yamlQuote(p.join(sdk.packagesDir, package))}');
    }
    return out.toString();
  }

  /// Um path como scalar YAML, entre aspas — um caminho com espaço (ou
  /// backslash, no Windows) quebra como scalar puro, e o YAML nem reclama:
  /// lê o path truncado.
  static String _yamlQuote(String path) =>
      '"${path.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}
