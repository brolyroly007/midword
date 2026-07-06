#Requires AutoHotkey v2.0
; ============================================================
; Prueba de humo end-to-end de Midword.
; Lanza midword.ahk con un atajos.txt temporal, abre Notepad,
; escribe //qatest + Tab y verifica que la expansión ocurrió
; (leyendo el texto vía Ctrl+A/Ctrl+C). Limpia todo al salir.
;
; Uso:  AutoHotkey64.exe tests\qa_smoke.ahk
; Salida: "SMOKE OK" y exit 0, o "SMOKE FALLA: …" y exit 1.
; Nota: escribe teclas reales — no muevas el mouse/teclado
; durante los ~10 segundos que dura.
; ============================================================
#SingleInstance Force
SendMode "Event"
SetKeyDelay(40, 20)
SendLevel 2          ; para que el InputHook de midword (I1) nos vea

repo := RegExReplace(A_ScriptDir, "\\tests$")
EXPECTED := "EXPANSION-OK-12345"
midPid := 0
tmp := A_Temp "\midword-qa-" A_TickCount

Cleanup() {
    global
    try if midPid
        ProcessClose(midPid)
    try DirDelete(tmp, 1)
}

Fail(msg) {
    FileAppend("SMOKE FALLA: " msg "`n", "*", "UTF-8")
    Cleanup()
    ExitApp(1)
}

; 1) entorno temporal: midword.ahk + atajos.txt solo con el atajo de prueba
DirCreate(tmp)
FileCopy(repo "\midword.ahk", tmp "\midword.ahk", 1)
FileAppend("qatest=" EXPECTED "`n", tmp "\atajos.txt", "UTF-8")

; 2) lanzar la instancia de prueba de midword
Run('"' A_AhkPath '" "' tmp '\midword.ahk"', , , &midPid)
Sleep 2500
if !ProcessExist(midPid)
    Fail("midword no sobrevivió al arranque (revisa " tmp "\midword.log)")

; 3) campo de texto propio (Edit de este mismo script): recibe las
; teclas y el pegado de midword, y se lee directo sin clipboard
g := Gui("+AlwaysOnTop", "QA Midword")
ed := g.Add("Edit", "w420 h120")
g.Show()
WinActivate(g.Hwnd)
if !WinWaitActive(g.Hwnd, , 5)
    Fail("la ventana de prueba no obtuvo el foco")
ed.Focus()
Sleep 500

; 4) escribir el atajo y aceptar con Tab
Send("//qatest")
Sleep 900            ; que el menú aparezca
Send("{Tab}")
Sleep 1800           ; borrado + pegado + restauración del clipboard

; 5) verificar
got := Trim(ed.Value, " `t`r`n")
if got != EXPECTED
    Fail("texto inesperado: '" got "' (se esperaba '" EXPECTED "')")

FileAppend("SMOKE OK — //qatest se expandió correctamente`n", "*", "UTF-8")
Cleanup()
ExitApp(0)
