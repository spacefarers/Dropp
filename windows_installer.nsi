; Dropp Windows Installer Script
; NSIS (Nullsoft Scriptable Install System) script

!include "MUI2.nsh"
!include "FileFunc.nsh"

; General settings
Name "Dropp"
OutFile "Dropp_Setup.exe"
Unicode True
InstallDir "$PROGRAMFILES\Dropp"
InstallDirRegKey HKCU "Software\Dropp" ""
RequestExecutionLevel admin

; Interface settings
!define MUI_ABORTWARNING
!define MUI_ICON "icons\dropp.ico"
!define MUI_UNICON "icons\dropp.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "icons\shelf_icon.png"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "icons\shelf_icon.png"
!define MUI_HEADERIMAGE_RIGHT

; Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "LICENSE.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; Languages
!insertmacro MUI_LANGUAGE "English"

; Installer sections
Section "Dropp" SecDropp
    SetOutPath "$INSTDIR"
    
    ; Copy all files from the dist directory
    File /r "dist\Dropp\*.*"
    
    ; Create uninstaller
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    
    ; Create shortcuts
    CreateDirectory "$SMPROGRAMS\Dropp"
    CreateShortcut "$SMPROGRAMS\Dropp\Dropp.lnk" "$INSTDIR\Dropp.exe"
    CreateShortcut "$SMPROGRAMS\Dropp\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
    CreateShortcut "$DESKTOP\Dropp.lnk" "$INSTDIR\Dropp.exe"
    
    ; Add to Add/Remove Programs
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Dropp" "DisplayName" "Dropp"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Dropp" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Dropp" "DisplayIcon" "$INSTDIR\Dropp.exe"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Dropp" "Publisher" "Dropp"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Dropp" "DisplayVersion" "1.0.0"
    
    ; Add to startup
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "Dropp" "$INSTDIR\Dropp.exe"
    
    ; Get estimated size
    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Dropp" "EstimatedSize" "$0"
SectionEnd

; Uninstaller section
Section "Uninstall"
    ; Remove files and directories
    Delete "$INSTDIR\Uninstall.exe"
    RMDir /r "$INSTDIR"
    
    ; Remove shortcuts
    Delete "$SMPROGRAMS\Dropp\Dropp.lnk"
    Delete "$SMPROGRAMS\Dropp\Uninstall.lnk"
    RMDir "$SMPROGRAMS\Dropp"
    Delete "$DESKTOP\Dropp.lnk"
    
    ; Remove registry entries
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Dropp"
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "Dropp"
    DeleteRegKey HKCU "Software\Dropp"
SectionEnd