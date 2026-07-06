@echo off
rem Quita el acceso directo de la carpeta Inicio: Midword ya no arrancara con Windows
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Midword.lnk" 2>nul
echo Listo: Midword ya no se iniciara automaticamente con Windows.
pause
