@echo off
rem Crea un acceso directo en la carpeta Inicio para que Midword arranque con Windows
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Midword.lnk'); $s.TargetPath='D:\atajos\Midword.exe'; $s.WorkingDirectory='D:\atajos'; $s.Save()"
echo Listo: Midword se iniciara automaticamente con Windows.
pause
