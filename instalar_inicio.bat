@echo off
rem Crea un acceso directo en la carpeta Inicio para que Midword arranque con Windows
rem (usa la carpeta donde esta este .bat; no hace falta editar rutas)
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Midword.lnk'); $s.TargetPath='%~dp0Midword.exe'; $s.WorkingDirectory='%~dp0'; $s.Save()"
echo Listo: Midword se iniciara automaticamente con Windows.
echo (Tambien puedes activarlo/desactivarlo desde el menu de la bandeja de Midword.)
pause
