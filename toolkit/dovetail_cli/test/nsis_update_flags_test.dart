import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

const Set<String> readByNsisItself = <String>{'/S'};

String renderedInstaller() {
  final BundleSpec spec = BundleSpec(
    productName: 'Example',
    manufacturer: 'Example Ltd',
    identifier: 'com.example.app',
    version: AppVersion.parse('1.2.3'),
    mainBinaryName: 'example',
    appDirectory: '/tmp/app',
    outputDirectory: '/tmp/out',
  );
  return '${NsisScript.render(spec, TargetArch.x86_64)}\n${NsisUtils.source}';
}

bool readByScript(String script, String flag) => script
    .split('\n')
    .any(
      (String line) =>
          line.contains(r'${GetOptions}') && line.contains('"$flag"'),
    );

List<String> unreadFlags(String script, WindowsInstallMode mode) => <String>[
  for (final String flag in WindowsInstaller(
    runner: const SystemProcessRunner(),
    mode: mode,
  ).argumentsFor('.exe', r'C:\t\setup.exe'))
    if (!readByNsisItself.contains(flag) && !readByScript(script, flag)) flag,
];

void main() {
  final String script = renderedInstaller();

  for (final WindowsInstallMode mode in WindowsInstallMode.values) {
    test(
      'the ${mode.name} update should pass only flags the installer reads',
      () {
        expect(unreadFlags(script, mode), isEmpty);
      },
    );
  }
}
