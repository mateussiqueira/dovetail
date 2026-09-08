abstract final class NsisUtils {
  static const String source = r'''
!ifndef DOVETAIL_UTILS_INCLUDED
!define DOVETAIL_UTILS_INCLUDED

!include LogicLib.nsh

!macro CheckIfAppIsRunning UN executableName productName
  !define UniqueID ${__LINE__}

  nsExec::ExecToStack 'cmd /c tasklist /NH /FI "IMAGENAME eq ${executableName}"'
  Pop $R0
  Pop $R1

  ${If} $R0 == 0
    Push $R1
    Push "${executableName}"
    Call ${UN}DovetailStrContains
    Pop $R2
    ${If} $R2 != ""
      DetailPrint "Closing ${productName}..."
      nsExec::Exec 'taskkill /F /IM "${executableName}" /T'
      Pop $R0
      Sleep 500

      nsExec::ExecToStack 'cmd /c tasklist /NH /FI "IMAGENAME eq ${executableName}"'
      Pop $R0
      Pop $R1
      Push $R1
    Push "${executableName}"
    Call ${UN}DovetailStrContains
    Pop $R2
      ${If} $R2 != ""
        ${If} ${Silent}
          SetErrorLevel 2
        ${EndIf}
        MessageBox MB_OK|MB_ICONSTOP "${productName} is still running. Close it and run this installer again."
        Abort
      ${EndIf}
    ${EndIf}
  ${EndIf}

  !undef UniqueID
!macroend

!macro DovetailStrContainsBody UN
Function ${UN}DovetailStrContains
  Exch $R0
  Exch
  Exch $R1
  Push $R2
  Push $R3
  Push $R4

  StrCpy $R2 ""
  StrLen $R3 $R0
  StrCpy $R4 0

  loop:
    StrCpy $R2 $R1 $R3 $R4
    StrCmp $R2 $R0 found
    StrCmp $R2 "" notFound
    IntOp $R4 $R4 + 1
    Goto loop

  found:
    StrCpy $R2 $R0
    Goto done

  notFound:
    StrCpy $R2 ""

  done:
    StrCpy $R0 $R2
    Pop $R4
    Pop $R3
    Pop $R2
    Pop $R1
    Exch $R0
FunctionEnd
!macroend

!insertmacro DovetailStrContainsBody ""
!insertmacro DovetailStrContainsBody "un."

!endif
''';
}
