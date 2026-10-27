#ifndef AppVersion
  #error AppVersion is required
#endif
[Setup]
AppId=app.zhixu.desktop.windows
AppName=枝序
AppVersion={#AppVersion}
AppPublisher=zoulirise
AppPublisherURL=https://github.com/zoulirise-dev/zhixu
AppSupportURL=https://github.com/zoulirise-dev/zhixu/issues
DefaultDirName={localappdata}\Programs\Zhixu
DefaultGroupName=枝序
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UsePreviousAppDir=yes
UsePreviousLanguage=yes
DisableDirPage=auto
DisableProgramGroupPage=yes
AppMutex=Local\ZhixuDesktopApp
CloseApplications=no
RestartApplications=no
UninstallDisplayIcon={app}\zhixu.exe
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
LicenseFile={#StageDir}\LICENSE.txt
OutputDir={#OutputDir}
OutputBaseFilename=Zhixu-{#AppVersion}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[InstallDelete]
Type: files; Name: "{app}\使用说明-README.txt"
[Icons]
Name: "{autoprograms}\枝序"; Filename: "{app}\zhixu.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\枝序"; Filename: "{app}\zhixu.exe"; WorkingDir: "{app}"; Tasks: desktopicon
[Run]
Filename: "{app}\zhixu.exe"; Description: "{cm:LaunchProgram,枝序}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
