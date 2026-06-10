@echo off
rem Crea un acceso directo en la carpeta Inicio para que Atajos arranque con Windows
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Atajos.lnk'); $s.TargetPath='D:\atajos\Atajos.exe'; $s.WorkingDirectory='D:\atajos'; $s.Save()"
echo Listo: Atajos se iniciara automaticamente con Windows.
pause
