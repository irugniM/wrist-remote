@echo off
rem Builds WristRemote.exe with the C# compiler that ships with Windows (.NET Framework 4.8).
rem Reading "now playing" uses the Windows Runtime media API, so the build needs the
rem Windows 10/11 SDK metadata (Windows.winmd). The finished exe needs nothing extra.
setlocal
set FW=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319
set WINMD=
for /d %%D in ("%ProgramFiles(x86)%\Windows Kits\10\UnionMetadata\10.*") do (
  if exist "%%D\Windows.winmd" set WINMD=%%D\Windows.winmd
)
if "%WINMD%"=="" (
  echo Windows SDK metadata not found. Install the Windows 10/11 SDK.
  exit /b 1
)
cd /d "%~dp0"
"%FW%\csc.exe" /nologo /target:winexe /optimize+ /out:WristRemote.exe /win32icon:WristRemote.ico ^
  /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:Microsoft.CSharp.dll ^
  /r:"%FW%\System.Net.Http.dll" /r:"%FW%\System.Web.Extensions.dll" ^
  /r:"%FW%\System.Runtime.dll" /r:"%FW%\System.Runtime.WindowsRuntime.dll" /r:"%WINMD%" ^
  WristRemote.cs Status.cs Meeting.cs
