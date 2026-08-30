; MiruShin Windows Installer Script
; Usage from project root:
;   iscc /DMyAppVersion=X.X.X /DMySourceDir=<abs-path-to-Release-folder> windows\installer\mirushin.iss

#define MyAppName     "MiruShin"
#define MyAppPublisher "emp0ry"
#define MyAppURL      "https://github.com/emp0ry/MiruShin"
#define MyAppExeName  "mirushin.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases/latest
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=.
OutputBaseFilename=MiruShin-windows-v{#MyAppVersion}-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
const
  MiruShinProtocolKey = 'Software\Classes\mirushin';
  MiruShinProtocolCommandKey = 'Software\Classes\mirushin\shell\open\command';

function InstalledProtocolCommand: String;
begin
  Result := '"' + ExpandConstant('{app}\{#MyAppExeName}') + '" "%1"';
end;

procedure RegisterMiruShinProtocol;
begin
  RegWriteStringValue(HKCU, MiruShinProtocolKey, '', 'URL:MiruShin Protocol');
  RegWriteStringValue(HKCU, MiruShinProtocolKey, 'URL Protocol', '');
  RegWriteStringValue(
    HKCU,
    MiruShinProtocolCommandKey,
    '',
    InstalledProtocolCommand
  );
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    RegisterMiruShinProtocol;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  CurrentCommand: String;
begin
  if (CurUninstallStep = usUninstall) and
     RegQueryStringValue(
       HKCU,
       MiruShinProtocolCommandKey,
       '',
       CurrentCommand
     ) and
     (CompareText(CurrentCommand, InstalledProtocolCommand) = 0) then
    RegDeleteKeyIncludingSubkeys(HKCU, MiruShinProtocolKey);
end;
