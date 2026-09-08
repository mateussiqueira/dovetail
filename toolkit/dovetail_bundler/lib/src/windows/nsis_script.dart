import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:dovetail_bundler/src/spec/staged_file.dart';
import 'package:dovetail_bundler/src/windows/nsis_text.dart';

abstract final class NsisScript {
  static String render(
    BundleSpec spec,
    TargetArch arch, {
    bool unicode = true,
  }) {
    final StringBuffer out = StringBuffer();

    out.writeln('Unicode ${unicode ? 'true' : 'false'}');
    out.writeln('ManifestDPIAware true');
    out.writeln('ManifestDPIAwareness PerMonitorV2');
    out.writeln('SetCompressor /SOLID lzma');
    out.writeln();
    out.writeln(r'!addplugindir /x86-unicode "${PLUGINDIR}"');
    out.writeln();
    out.writeln('!include MUI2.nsh');
    out.writeln('!include FileFunc.nsh');
    out.writeln('!include LogicLib.nsh');
    out.writeln('!include x64.nsh');
    out.writeln();
    out.writeln(NsisText.define('PRODUCTNAME', spec.productName));
    out.writeln(NsisText.define('MANUFACTURER', spec.manufacturer));
    out.writeln(NsisText.define('BUNDLEID', spec.identifier));
    out.writeln(NsisText.define('VERSION', spec.version.semantic));
    out.writeln(NsisText.define('MAINBINARYNAME', spec.mainBinaryName));
    out.writeln(
      r'!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCTNAME}"',
    );
    out.writeln(r'!define MANUKEY "Software\${MANUFACTURER}"');
    out.writeln(r'!define MANUPRODUCTKEY "${MANUKEY}\${PRODUCTNAME}"');
    out.writeln();
    out.writeln('!include "dovetail_utils.nsh"');
    out.writeln();

    final String? hooks = spec.installerHooks;
    if (hooks != null) {
      out.writeln('!include "${NsisText.escape(hooks)}"');
      out.writeln();
    }

    out.writeln(r'Name "${PRODUCTNAME}"');
    out.writeln(
      'OutFile "${NsisText.escape(spec.installerFileNameFor(arch))}"',
    );
    out.writeln('RequestExecutionLevel ${spec.installMode.executionLevel}');
    out.writeln(
      'InstallDir "${spec.installMode.defaultRoot}\\\${PRODUCTNAME}"',
    );
    out.writeln('VIProductVersion "${spec.version.windowsFileVersion}"');
    out.writeln(r'VIAddVersionKey "ProductName" "${PRODUCTNAME}"');
    out.writeln(r'VIAddVersionKey "CompanyName" "${MANUFACTURER}"');
    out.writeln(r'VIAddVersionKey "FileVersion" "${VERSION}"');
    out.writeln(r'VIAddVersionKey "ProductVersion" "${VERSION}"');
    out.writeln();

    final String? icon = spec.installerIcon;
    if (icon != null) {
      out.writeln('!define MUI_ICON "${NsisText.escape(icon)}"');
    }
    out.writeln('!insertmacro MUI_PAGE_WELCOME');
    final String? license = spec.licenseFile;
    if (license != null) {
      out.writeln(
        '!insertmacro MUI_PAGE_LICENSE "${NsisText.escape(license)}"',
      );
    }
    out.writeln('!insertmacro MUI_PAGE_DIRECTORY');
    out.writeln('!insertmacro MUI_PAGE_INSTFILES');
    out.writeln('!insertmacro MUI_PAGE_FINISH');
    out.writeln('!insertmacro MUI_UNPAGE_CONFIRM');
    out.writeln('!insertmacro MUI_UNPAGE_INSTFILES');
    if (spec.offersLanguageChoice) {
      out.writeln(r'!define MUI_LANGDLL_REGISTRY_ROOT "HKCU"');
      out.writeln(r'!define MUI_LANGDLL_REGISTRY_KEY "${MANUPRODUCTKEY}"');
      out.writeln(
        r'!define MUI_LANGDLL_REGISTRY_VALUENAME "InstallerLanguage"',
      );
    }
    for (final String language in spec.installerLanguages) {
      out.writeln('!insertmacro MUI_LANGUAGE "${NsisText.escape(language)}"');
    }
    out.writeln();

    out.writeln('Function .onInit');
    if (spec.offersLanguageChoice) {
      out.writeln('  !insertmacro MUI_LANGDLL_DISPLAY');
    }
    out.writeln('  SetShellVarContext ${spec.installMode.shellContext}');
    out.writeln(r'  ${If} ${RunningX64}');
    out.writeln('    SetRegView 64');
    out.writeln(r'  ${EndIf}');
    out.writeln('FunctionEnd');
    out.writeln();

    out.writeln('Section Install');
    out.writeln(r'  SetOutPath $INSTDIR');
    out.writeln('  !ifmacrodef NSIS_HOOK_PREINSTALL');
    out.writeln('    !insertmacro NSIS_HOOK_PREINSTALL');
    out.writeln('  !endif');
    out.writeln(
      r'  !insertmacro CheckIfAppIsRunning "" "${MAINBINARYNAME}.exe" "${PRODUCTNAME}"',
    );
    out.writeln(r'  File /r "$%DOVETAIL_APP_DIR%\*.*"');
    for (final StagedFile file in spec.extraFiles) {
      out.writeln(
        '  SetOutPath "\$INSTDIR\\${NsisText.escape(file.destination)}"',
      );
      out.writeln('  File "${NsisText.escape(file.source)}"');
    }
    out.writeln(r'  SetOutPath $INSTDIR');
    out.writeln(r'  WriteUninstaller "$INSTDIR\uninstall.exe"');
    out.writeln(r'  WriteRegStr SHCTX "${MANUPRODUCTKEY}" "" $INSTDIR');
    out.writeln(
      r'  WriteRegStr SHCTX "${UNINSTKEY}" "DisplayName" "${PRODUCTNAME}"',
    );
    out.writeln(
      r'  WriteRegStr SHCTX "${UNINSTKEY}" "DisplayVersion" "${VERSION}"',
    );
    out.writeln(
      r'  WriteRegStr SHCTX "${UNINSTKEY}" "Publisher" "${MANUFACTURER}"',
    );
    out.writeln(
      r'  WriteRegStr SHCTX "${UNINSTKEY}" "UninstallString" "$INSTDIR\uninstall.exe"',
    );
    out.writeln(
      r'  WriteRegStr SHCTX "${UNINSTKEY}" "InstallLocation" "$INSTDIR"',
    );
    out.writeln(
      r'  WriteRegStr SHCTX "${UNINSTKEY}" "MainBinaryName" "${MAINBINARYNAME}.exe"',
    );
    out.writeln(r'  WriteRegDWORD SHCTX "${UNINSTKEY}" "NoModify" 1');
    out.writeln(r'  WriteRegDWORD SHCTX "${UNINSTKEY}" "NoRepair" 1');
    final String? homepage = spec.homepage;
    if (homepage != null) {
      out.writeln(
        '  WriteRegStr SHCTX "\${UNINSTKEY}" "URLInfoAbout" '
        '"${NsisText.escape(homepage)}"',
      );
    }
    out.writeln('  !ifmacrodef NSIS_HOOK_POSTINSTALL');
    out.writeln('    !insertmacro NSIS_HOOK_POSTINSTALL');
    out.writeln('  !endif');
    out.writeln('SectionEnd');
    out.writeln();

    out.writeln('Section Uninstall');
    out.writeln('  !ifmacrodef NSIS_HOOK_PREUNINSTALL');
    out.writeln('    !insertmacro NSIS_HOOK_PREUNINSTALL');
    out.writeln('  !endif');
    out.writeln(
      r'  !insertmacro CheckIfAppIsRunning "un." "${MAINBINARYNAME}.exe" "${PRODUCTNAME}"',
    );
    out.writeln(r'  RMDir /r "$INSTDIR"');
    out.writeln(r'  DeleteRegKey SHCTX "${UNINSTKEY}"');
    out.writeln(r'  DeleteRegKey SHCTX "${MANUPRODUCTKEY}"');
    out.writeln('  !ifmacrodef NSIS_HOOK_POSTUNINSTALL');
    out.writeln('    !insertmacro NSIS_HOOK_POSTUNINSTALL');
    out.writeln('  !endif');
    out.writeln('SectionEnd');

    return out.toString();
  }
}
