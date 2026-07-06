; Instalador de Midword para quien prefiere "siguiente, siguiente, listo".
; Compilar con Inno Setup 6:  ISCC.exe midword.iss
; (el zip portable de Releases sigue siendo la opción recomendada)

#define MyVersion "1.3.0"

[Setup]
AppId={{8F1B7A64-9C1E-4D2B-B7B4-MIDWORD00001}
AppName=Midword
AppVersion={#MyVersion}
AppPublisher=brolyroly007
AppPublisherURL=https://github.com/brolyroly007/midword
AppSupportURL=https://github.com/brolyroly007/midword/issues
DefaultDirName={autopf}\Midword
DefaultGroupName=Midword
OutputBaseFilename=MidwordSetup-{#MyVersion}
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\Midword.exe
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
Source: "..\Midword.exe"; DestDir: "{app}"
Source: "..\atajos.ejemplo.txt"; DestDir: "{app}"
Source: "..\LEEME.txt"; DestDir: "{app}"; Flags: isreadme
Source: "..\PROMPT_PARA_IA.txt"; DestDir: "{app}"
Source: "..\midword.ico"; DestDir: "{app}"

[Tasks]
Name: "startup"; Description: "Iniciar Midword automáticamente con Windows"

[Icons]
Name: "{group}\Midword"; Filename: "{app}\Midword.exe"
Name: "{group}\Editar atajos"; Filename: "{app}\atajos.txt"
Name: "{userstartup}\Midword"; Filename: "{app}\Midword.exe"; Tasks: startup

[Run]
Filename: "{app}\Midword.exe"; Description: "Abrir Midword ahora"; Flags: nowait postinstall skipifsilent
