# Valida atajos.ahk, lo recompila a Atajos.exe y lo reinicia
$ahk = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
$src = 'D:\atajos\atajos.ahk'

& $ahk /ErrorStdOut /validate $src 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host "FALLO VALIDACION (exit=$LASTEXITCODE)"
    exit 1
}
Write-Host 'VALIDACION OK'

Stop-Process -Name Atajos -Force -ErrorAction SilentlyContinue
Start-Sleep 1

& 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe' /in $src /out 'D:\atajos\Atajos.exe' `
    /base $ahk /icon 'D:\atajos\atajos.ico' /silent verbose | Out-String
Start-Sleep 6

if (-not (Test-Path 'D:\atajos\Atajos.exe')) {
    Write-Host 'FALLO COMPILACION'
    exit 1
}
# vía explorer para que el proceso no muera al cerrar esta consola
explorer.exe 'D:\atajos\Atajos.exe'
Start-Sleep 2
Get-Process Atajos -ErrorAction SilentlyContinue | Select-Object Name, Id | Format-Table
