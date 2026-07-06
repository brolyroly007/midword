# Valida midword.ahk, lo recompila a Midword.exe y lo reinicia
# (rutas relativas a la carpeta del script; no hace falta editarlas)
$ahk     = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
$ahk2exe = 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe'
$src  = Join-Path $PSScriptRoot 'midword.ahk'
$out  = Join-Path $PSScriptRoot 'Midword.exe'
$icon = Join-Path $PSScriptRoot 'midword.ico'

foreach ($tool in $ahk, $ahk2exe) {
    if (-not (Test-Path $tool)) { Write-Host "No se encontro: $tool"; exit 1 }
}

& $ahk /ErrorStdOut /validate $src 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host "FALLO VALIDACION (exit=$LASTEXITCODE)"
    exit 1
}
Write-Host 'VALIDACION OK'

& $ahk /ErrorStdOut $src --selftest 2>&1 | Out-String | Write-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "FALLO SELFTEST (exit=$LASTEXITCODE)"
    exit 1
}

# Compila a un temporal: si la compilacion falla, el exe actual y el
# proceso en ejecucion quedan intactos.
$tmp = Join-Path $PSScriptRoot 'Midword.new.exe'
Remove-Item $tmp -ErrorAction SilentlyContinue
& $ahk2exe /in $src /out $tmp /base $ahk /icon $icon /silent verbose | Out-String

# Ahk2Exe termina de escribir el exe de forma asincrona: esperar con timeout
$deadline = (Get-Date).AddSeconds(30)
while (-not (Test-Path $tmp) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
if (-not (Test-Path $tmp)) {
    Write-Host 'FALLO COMPILACION'
    exit 1
}

Stop-Process -Name Midword -Force -ErrorAction SilentlyContinue
Start-Sleep 1
Move-Item $tmp $out -Force

# via explorer para que el proceso no muera al cerrar esta consola
explorer.exe $out
Start-Sleep 2
Get-Process Midword -ErrorAction SilentlyContinue | Select-Object Name, Id | Format-Table
