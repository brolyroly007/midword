; ============================================================
;  Midword — expansor de texto global con autocompletado
;  Tema visual: paleta RedactorIA / BiPe Alerta
;  (crema #F0EEE6, blanco, carbón #141413, verde salvia #6A9E8C)
;
;  Escribe //atajo en cualquier aplicación y aparecerá un menú
;  de sugerencias. Tab o Enter inserta el texto completo.
;  Los grupos se muestran como UNA fila y se desglosan en
;  submenús al pasar el mouse o seleccionarlos (hasta 2 niveles).
;
;  Formato de atajos.txt:
;    atajo=texto                    atajo normal
;    atajo!=texto                   expansión instantánea (sin Tab)
;    atajo[5|10|15]=...{1}...       grupo de 1 nivel
;    atajo[a:Et A|b:Et B][5|10]=    grupo de 2 niveles; "a" va al
;        ...{1}...{2}...            nombre (//atajoa5) y "Et A" al texto
;    # comentario
;  Dentro del texto: \n salto de línea, {fecha} {hora} {dia}
;  {fecha_larga} se reemplazan al insertar, {cursor} deja el
;  cursor en esa posición, {1}/{2} = opción elegida de cada nivel.
; ============================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SendMode "Input"

VERSION := "1.3.0"
;@Ahk2Exe-SetName Midword
;@Ahk2Exe-SetDescription Midword — expansor de texto con autocompletado
;@Ahk2Exe-SetVersion 1.3.0
;@Ahk2Exe-SetCopyright MIT — github.com/brolyroly007/midword

CONFIG := A_ScriptDir "\atajos.txt"

; --- Opciones (midword.ini es opcional; si no existe se usan los defaults) ---
;   [opciones]
;   prefijo=;;             → activador en vez de //
;   min_caracteres=1       → no mostrar el menú hasta escribir N letras tras el prefijo
;   max_filas=10           → filas visibles del menú (3–20)
;   delay_pegar=250        → ms de espera tras pegar antes de restaurar el portapapeles
;   delay_archivo=1200     → ídem para atajos de archivo
;   apps_excluidas=Code.exe|WindowsTerminal.exe → no sugerir en esas apps
;   sonido=1               → bip suave al insertar
;   tema=oscuro            → menú oscuro (claro | oscuro | auto; default auto)
;   hotkey_pausa=^!m       → atajo para pausar/reanudar (sintaxis de hotkeys de AHK)
;   hotkey_gestor=^!g      → atajo para abrir el gestor
INI := A_ScriptDir "\midword.ini"
OptGet(key, def) {
    try return IniRead(INI, "opciones", key, def)
    return def
}
PREFIX := OptGet("prefijo", "//")
MIN_CHARS := 0
try MIN_CHARS := Integer(OptGet("min_caracteres", "0"))
MAX_ROWS := 10
try MAX_ROWS := Max(3, Min(20, Integer(OptGet("max_filas", "10"))))
DELAY_PEGAR := 250
try DELAY_PEGAR := Max(0, Integer(OptGet("delay_pegar", "250")))
DELAY_ARCHIVO := 1200
try DELAY_ARCHIVO := Max(0, Integer(OptGet("delay_archivo", "1200")))
SONIDO := OptGet("sonido", "0") = "1"

; --- Contador de uso por atajo (uso.ini): rankea las sugerencias ---
USE_FILE := A_ScriptDir "\uso.ini"
useCount := Map(), useCount.CaseSense := "Off"
try {
    if FileExist(USE_FILE) {
        for pair in StrSplit(IniRead(USE_FILE, "uso"), "`n") {
            eq := InStr(pair, "=")
            if eq
                useCount[SubStr(pair, 1, eq - 1)] := Integer(SubStr(pair, eq + 1))
        }
    }
}
APPS_EXCL := []
for a in StrSplit(OptGet("apps_excluidas", ""), "|")
    if Trim(a) != ""
        APPS_EXCL.Push(StrLower(Trim(a)))

; --- Selftest del parser:  AutoHotkey64.exe midword.ahk --selftest ---
; Solo usa funciones puras (no toca atajos.txt ni crea GUI). Sale con
; código 0 si todo pasa; lo corren el CI y recompilar.ps1.
if A_Args.Length && A_Args[1] = "--selftest"
    ExitApp(RunSelfTest())

RunSelfTest() {
    fails := 0, out := ""
    T(name, cond) {
        if !cond {
            fails++
            out .= "FALLA: " name "`n"
        }
    }
    T("AutoTok básico", AutoTok("APA 7") = "apa7")
    T("AutoTok número gana", AutoTok("10 páginas") = "10")
    T("AutoTok tildes/ñ", AutoTok("Añadir Sección") = "anadirsecc")
    l := ParseLevel("5`n10`napa: APA 7")
    T("ParseLevel largo", l.Length = 3)
    T("ParseLevel tok automático", l[1].tok = "5" && l[1].lab = "5")
    T("ParseLevel tok manual", l[3].tok = "apa" && l[3].lab = "APA 7")
    s := SerializeAtajo("con", 0, "texto {1} soles", l, [])
    T("Serialize grupo", s = "con[5|10|apa:APA 7]=texto {1} soles")
    T("Serialize instantáneo", SerializeAtajo("ok", 1, "a`nb", [], []) = "ok!=a\nb")
    rt := ParseLevel(LevelToText(l))
    T("Roundtrip nivel", rt.Length = 3 && rt[3].tok = "apa" && rt[3].lab = "APA 7")
    T("BSLen ascii", BSLen("hola") = 4)
    T("BSLen emoji", BSLen("hi😊") = 3)
    T("JoinNums", JoinNums([1, 2, 3]) = "1, 2, 3")
    T("Norm tildes/ñ", Norm("Canción Ñoña") = "cancion nona")
    T("Fuzzy encuentra", FuzzyMatch("grc", "gracias") = true)
    T("Fuzzy rechaza", FuzzyMatch("xyz", "gracias") = false)
    T("Fuzzy corto no aplica", FuzzyMatch("g", "gracias") = false)
    T("Serialize escapa \n literal", SerializeAtajo("x", 0, "a\nb", [], []) = "x=a\\nb")
    T("Serialize escapa tab", SerializeAtajo("x", 0, "a" A_Tab "b", [], []) = "x=a\tb")
    FileAppend(fails ? out : "SELFTEST OK (18 pruebas)`n", "*", "UTF-8")
    return fails
}

; --- Errores de runtime: registrar en midword.log en vez del diálogo crudo ---
OnError(LogError)
LogError(err, mode) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " err.Message
        "  (" err.What ", línea " err.Line ")`n", A_ScriptDir "\midword.log", "UTF-8")
    TrayTip("Error interno registrado en midword.log", "Midword", "Icon!")
    return 1
}

; --- Paleta (de colors.xml de BiPe Alerta) ---
CLR_BG       := "F0EEE6"   ; ra_bg — crema, header
CLR_SURFACE  := "FFFFFF"   ; ra_surface — fondo de tarjeta
CLR_SURF_ALT := "FAFAF8"   ; ra_surface_alt — footer
CLR_TEXT     := "141413"   ; ra_text
CLR_BODY     := "333330"   ; ra_text_body — texto de vista previa
CLR_MUTED    := "7A7A72"   ; ra_text_muted — hints
CLR_ACCENT   := "6A9E8C"   ; ra_accent — verde salvia
CLR_ACC_DARK := "4A7C5F"   ; ra_accent_dark — texto del atajo
CLR_ACC_LITE := "E8F0EC"   ; ra_accent_light — fila seleccionada
CLR_BORDER   := "E5E3DA"   ; border_light — borde de la tarjeta
CLR_RED      := "C64B4B"   ; status_inactive
CLR_RED_LITE := "F6E2E2"   ; rojo suave para el botón eliminar
CLR_ONDARK   := "B7B6AE"   ; texto atenuado sobre el hero oscuro

; --- Tema del menú de sugerencias (el gestor mantiene el tema claro) ---
; midword.ini: tema=claro | oscuro | auto (default: auto = según Windows)
TEMA := StrLower(OptGet("tema", "auto"))
darkMenu := TEMA = "oscuro"
if TEMA = "auto"
    try darkMenu := !RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme")
if darkMenu {
    MNU_BG := "2A2A26", MNU_SURFACE := "1F1F1D", MNU_SURF_ALT := "262623"
    MNU_BODY := "D6D5CE", MNU_MUTED := "8F8F86", MNU_ACCENT := "6A9E8C"
    MNU_ACC_DARK := "8FBFA9", MNU_ACC_LITE := "2F3D37", MNU_BORDER := "3B3B37"
} else {
    MNU_BG := CLR_BG, MNU_SURFACE := CLR_SURFACE, MNU_SURF_ALT := CLR_SURF_ALT
    MNU_BODY := CLR_BODY, MNU_MUTED := CLR_MUTED, MNU_ACCENT := CLR_ACCENT
    MNU_ACC_DARK := CLR_ACC_DARK, MNU_ACC_LITE := CLR_ACC_LITE, MNU_BORDER := CLR_BORDER
}

; --- Datos ---
rawLines := []          ; líneas del archivo tal cual (para editar sin perder comentarios)
shortcuts := Map()      ; atajo -> texto completo (incluye variantes)
instant := Map()        ; atajos con expansión instantánea (atajo!=...)
order := []             ; entradas en orden del archivo:
                        ;   {kind:"item",  trig}
                        ;   {kind:"group", name, dims, variants, template}
                        ;   dims = [nivel1, nivel2?], cada nivel = [{tok, lab}]
                        ;   ("name" y no "base": base es palabra reservada)
lastCfgTime := ""
sections := []          ; secciones "# ── Nombre ──" del archivo: {name, line}
userVars := Map()       ; variables de usuario:  $yape=999…  → {$yape}

; --- Estado del menú ---
typedBuf := ""          ; últimas teclas escritas por el usuario
curTyped := ""          ; lo escrito después de //
eraseLen := 0           ; caracteres a borrar al insertar
lastIns := ""           ; texto de la última expansión (para deshacer)
lastTypedTxt := ""      ; lo que el usuario había escrito (//atajo)
lastInsTick := 0        ; momento de la última expansión
expandCanceled := false ; el usuario canceló un {input:…} al expandir
suggesting := false
menuNav := false        ; el usuario ya navegó el menú (flechas/mouse)
entries := []           ; entradas mostradas en el menú principal
sugGui := 0
rows := []
rowByHwnd := Map()
selIdx := 1
menuX := 0, menuY := 0, menuHH := 0, menuRH := 0, menuW := 0
menuTW := 0             ; ancho de la columna del trigger (para reusar la GUI)
menuFooter := 0         ; control del pie "+N atajos más"
menuH := 0              ; alto de la ventana del menú (para el tooltip)
viewOff := 0            ; desplazamiento de scroll: fila i = entries[viewOff+i]
; submenú nivel 1
subGui := 0
subEntry := 0           ; entrada de grupo a la que pertenece
subRows := []
subByHwnd := Map()
subSel := 0
subActive := false
subForIdx := 0
subX := 0, subY := 0, subW := 0
; gestor de atajos
mgrGui := 0
mgrLV := 0, mgrSearch := 0, mgrName := 0, mgrInst := 0, mgrText := 0
mgrL1 := 0, mgrL2 := 0, mgrPrev := 0, mgrCount := 0
mgrRows := []           ; entrada de `order` por fila visible de la lista
mgrSelLine := 0         ; línea de atajos.txt en edición (0 = atajo nuevo)
mgrSelRaw := ""         ; contenido original de esa línea, para reubicarla
                        ; si el archivo cambió por fuera mientras se editaba
mgrNewSec := ""         ; sección donde insertar los atajos nuevos
mgrDirty := false       ; el formulario tiene cambios sin guardar
mgrCardL := 0, mgrCardR := 0, mgrPills := []   ; para el resize vertical
impGui := 0, impEdit := 0
; submenú nivel 2
sub2Gui := 0
sub2Items := []         ; triggers finales
sub2Rows := []
sub2ByHwnd := Map()
sub2Sel := 0
sub2Active := false
sub2ForIdx := 0

LoadShortcuts()

; --- Menú de la bandeja del sistema ---
paused := false
STARTUP_LNK := A_Startup "\Midword.lnk"
if FileExist(A_ScriptDir "\midword.ico")
    TraySetIcon(A_ScriptDir "\midword.ico")
A_IconTip := "Midword v" VERSION
A_TrayMenu.Delete()
A_TrayMenu.Add("Gestionar atajos…", OpenManager)
A_TrayMenu.Add("Ver todos los atajos", ShowAllFromTray)
A_TrayMenu.Add("Editar atajos (archivo)", EditConfig)
A_TrayMenu.Add("Recargar atajos", ReloadConfig)
A_TrayMenu.Add()
A_TrayMenu.Add("Pausar (no sugerir)", TogglePause)
A_TrayMenu.Add("Iniciar con Windows", ToggleStartup)
if FileExist(STARTUP_LNK)
    A_TrayMenu.Check("Iniciar con Windows")
A_TrayMenu.Add("Buscar actualización", CheckUpdate)
A_TrayMenu.Add()
A_TrayMenu.Add("Salir", (*) => ExitApp())

; consulta la última versión publicada en GitHub (solo al pedirlo)
CheckUpdate(*) {
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", "https://api.github.com/repos/brolyroly007/midword/releases/latest", true)
        req.SetRequestHeader("User-Agent", "Midword")
        req.Send()
        req.WaitForResponse(10)
        if RegExMatch(req.ResponseText, '"tag_name"\s*:\s*"v?([^"]+)"', &mv) {
            latest := mv[1]
            if VerCompare(latest, VERSION) > 0 {
                if MsgBox("Hay una versión nueva: v" latest " (tienes v" VERSION ").`n`n¿Abrir la página de descarga?", "Midword", "YesNo Iconi") = "Yes"
                    Run("https://github.com/brolyroly007/midword/releases/latest")
            } else {
                MsgBox("Estás en la última versión (v" VERSION ").", "Midword", "Iconi")
            }
        } else {
            MsgBox("No se pudo leer la respuesta de GitHub.", "Midword", "Icon!")
        }
    } catch as e {
        MsgBox("No se pudo comprobar (¿sin internet?): " e.Message, "Midword", "Icon!")
    }
}
A_TrayMenu.Default := "Gestionar atajos…"
TrayTip("Escribe " PREFIX "atajo en cualquier aplicación", "Midword activo")

; pausa/reanuda la captura de teclado (también vía hotkey_pausa del ini)
TogglePause(*) {
    global paused
    paused := !paused
    if paused {
        ih.Stop()
        ResetState()
        A_TrayMenu.Check("Pausar (no sugerir)")
        A_IconTip := "Midword v" VERSION " (en pausa)"
        TrayTip("En pausa: no se mostrarán sugerencias", "Midword")
    } else {
        ih.Start()
        A_TrayMenu.Uncheck("Pausar (no sugerir)")
        A_IconTip := "Midword v" VERSION
        TrayTip("Activo de nuevo", "Midword")
    }
}

; crea/quita el acceso directo de la carpeta Inicio del usuario
ToggleStartup(*) {
    if FileExist(STARTUP_LNK) {
        FileDelete(STARTUP_LNK)
        A_TrayMenu.Uncheck("Iniciar con Windows")
        TrayTip("Ya no se iniciará con Windows", "Midword")
    } else {
        FileCreateShortcut(A_ScriptFullPath, STARTUP_LNK, A_ScriptDir)
        A_TrayMenu.Check("Iniciar con Windows")
        TrayTip("Se iniciará automáticamente con Windows", "Midword")
    }
}

; --- Hook de teclado: solo observa, no bloquea nada ---
ih := InputHook("V I1")
ih.KeyOpt("{All}", "N")
ih.OnChar := HandleChar
ih.OnKeyDown := HandleKeyDown
ih.Start()
OnMessage(0x200, OnMouseMove)   ; hover del menú sin timer de polling
CoordMode "ToolTip", "Screen"   ; para la vista previa completa

; hotkeys opcionales del ini:  hotkey_pausa=^!m   hotkey_gestor=^!g
try {
    hk := OptGet("hotkey_pausa", "")
    if hk != ""
        Hotkey(hk, TogglePause)
}
try {
    hk := OptGet("hotkey_gestor", "")
    if hk != ""
        Hotkey(hk, OpenManager)
}

; --- Recarga automática cuando se edita atajos.txt ---
SetTimer(CheckConfigChanged, 3000)

; --- Teclas activas solo mientras el menú está visible ---
#HotIf suggesting && CanGoRight()
Right::GoRight()
#HotIf suggesting && (subActive || sub2Active)
Left::GoLeft()
; Tab/Enter solo se capturan con intención clara (algo escrito tras el
; prefijo, o navegación previa): un menú abierto por un simple "//" no
; roba el Tab/Enter que la aplicación necesitaba
#HotIf suggesting && (curTyped != "" || menuNav)
Tab::AcceptKey()
Enter::AcceptKey()
NumpadEnter::AcceptKey()
#HotIf suggesting
Esc::ResetState()
Down::NavKey(1)
Up::NavKey(-1)
; Alt+1..9 inserta la fila N directamente
!1::AcceptIndex(1)
!2::AcceptIndex(2)
!3::AcceptIndex(3)
!4::AcceptIndex(4)
!5::AcceptIndex(5)
!6::AcceptIndex(6)
!7::AcceptIndex(7)
!8::AcceptIndex(8)
!9::AcceptIndex(9)
#HotIf

~LButton:: {
    global
    if suggesting {
        MouseGetPos , , &hwnd
        if (sugGui && hwnd = sugGui.Hwnd) || (subGui && hwnd = subGui.Hwnd)
            || (sub2Gui && hwnd = sub2Gui.Hwnd)
            return
    }
    ResetState()
}
~RButton::ResetState()

; ==================== Configuración ====================

EditConfig(*) {
    Run('notepad.exe "' CONFIG '"')
}

ReloadConfig(*) {
    LoadShortcuts()
    TrayTip("Se recargaron " shortcuts.Count " atajos", "Midword")
}

CheckConfigChanged() {
    global lastCfgTime
    t := FileExist(CONFIG) ? FileGetTime(CONFIG) : ""
    if t != lastCfgTime {
        LoadShortcuts()
        if mgrGui        ; reflejar cambios externos en el gestor; la línea
            RefreshMgrList()   ; en edición se reubica por contenido al guardar
    }
}

LoadShortcuts() {
    global shortcuts, instant, order, lastCfgTime
    if !FileExist(CONFIG) {
        FileAppend(
            "# Atajos de texto — un atajo por línea, formato:  atajo=texto a insertar`n"
            "# atajo!=texto  →  expansión instantánea al terminar de escribirlo (sin Tab)`n"
            "# atajo[5|10]=texto con {1}  →  grupo desglosable: genera atajo5, atajo10…`n"
            "# Variables: {fecha} {hora} {dia} {fecha_larga} {cursor} — \n = salto de línea`n"
            "con=para confirmar y empezar es necesario el adelanto de una parte`n",
            CONFIG, "UTF-8")
    }
    lastCfgTime := FileGetTime(CONFIG)
    shortcuts := Map(), shortcuts.CaseSense := "Off"
    instant := Map(), instant.CaseSense := "Off"
    order := []
    global rawLines := StrSplit(StrReplace(ReadConfigText(), "`r"), "`n")
    while rawLines.Length && Trim(rawLines[rawLines.Length]) = ""
        rawLines.Pop()
    global sections := []
    global userVars := Map()
    userVars.CaseSense := "Off"
    curSec := ""
    badLines := [], extraDims := [], dupToks := [], dupNames := [], wsTrigs := []
    lineNo := 0
    for raw in rawLines {
        lineNo++
        line := Trim(raw)
        if line = "" || SubStr(line, 1, 1) = "#" {
            if RegExMatch(line, "^#\s*──\s*(.+?)\s*──", &ms) {
                curSec := ms[1]
                sections.Push({name: curSec, line: lineNo})
            }
            continue
        }
        pos := InStr(line, "=")
        if !pos {
            badLines.Push(lineNo)
            continue
        }
        ; variables de usuario:  $yape=999 999 999  → en textos como {$yape}
        if SubStr(line, 1, 1) = "$" {
            vName := Trim(SubStr(line, 2, pos - 2))
            if vName != ""
                userVars[vName] := StrReplace(SubStr(line, pos + 1), "\n", "`n")
            continue
        }
        trig := Trim(SubStr(line, 1, pos - 1))
        ; escapes: \\n → "\n" literal, \t → tabulador, \n → salto de línea
        txt := SubStr(line, pos + 1)
        txt := StrReplace(txt, "\\n", Chr(1))
        txt := StrReplace(txt, "\n", "`n")
        txt := StrReplace(txt, "\t", A_Tab)
        txt := StrReplace(txt, Chr(1), "\n")
        isInstant := false
        if SubStr(trig, -1) = "!" {
            isInstant := true
            trig := Trim(SubStr(trig, 1, -1))
        }
        if trig = ""
            continue
        ; grupos:  nombre[a|b]=  o  nombre[a:Etiqueta A|b][5|10]=
        if RegExMatch(trig, "^([^\[\]]+?)\s*((?:\[[^\]]+\])+)$", &mv) {
            dims := []
            p2 := 1
            while RegExMatch(mv[2], "\[([^\]]+)\]", &mb, p2) {
                d := []
                seenTok := Map(), seenTok.CaseSense := "Off"
                for o in StrSplit(mb[1], "|") {
                    o := Trim(o)
                    if o = ""
                        continue
                    c := InStr(o, ":")
                    tok := c ? Trim(SubStr(o, 1, c - 1)) : o
                    lab := c ? Trim(SubStr(o, c + 1)) : o
                    if seenTok.Has(tok) {  ; "10 páginas"|"10 días" → mismo atajo
                        dupToks.Push(lineNo)
                        continue
                    }
                    seenTok[tok] := true
                    d.Push({tok: tok, lab: lab})
                }
                if d.Length
                    dims.Push(d)
                p2 := mb.Pos + mb.Len
            }
            if !dims.Length
                continue
            if dims.Length > 2 {   ; solo hay submenús para 2 niveles
                extraDims.Push(lineNo)
                while dims.Length > 2
                    dims.Pop()
            }
            base := mv[1]
            variants := []
            hadDup := false
            if dims.Length = 1 {
                for o in dims[1] {
                    vTrig := base o.tok
                    hadDup := hadDup || shortcuts.Has(vTrig)
                    shortcuts[vTrig] := StrReplace(txt, "{1}", o.lab)
                    if isInstant
                        instant[vTrig] := true
                    variants.Push(vTrig)
                }
            } else {
                for o1 in dims[1] {
                    for o2 in dims[2] {
                        vTrig := base o1.tok o2.tok
                        hadDup := hadDup || shortcuts.Has(vTrig)
                        shortcuts[vTrig] := StrReplace(StrReplace(txt, "{1}", o1.lab), "{2}", o2.lab)
                        if isInstant
                            instant[vTrig] := true
                        variants.Push(vTrig)
                    }
                }
            }
            if hadDup
                dupNames.Push(lineNo)
            for v in variants {
                if RegExMatch(v, "\s") {   ; imposible de tipear
                    wsTrigs.Push(lineNo)
                    break
                }
            }
            order.Push({kind: "group", name: base, dims: dims, variants: variants, template: txt, line: lineNo, sec: curSec})
        } else {
            if shortcuts.Has(trig)
                dupNames.Push(lineNo)
            if RegExMatch(trig, "\s")
                wsTrigs.Push(lineNo)
            shortcuts[trig] := txt
            if isInstant
                instant[trig] := true
            order.Push({kind: "item", trig: trig, line: lineNo, sec: curSec})
        }
    }
    msg := ""
    if badLines.Length
        msg .= "Sin '=' (ignoradas): " JoinNums(badLines)
    if extraDims.Length
        msg .= (msg ? "`n" : "") "Más de 2 niveles [..] (se usan los 2 primeros): " JoinNums(extraDims)
    if dupToks.Length
        msg .= (msg ? "`n" : "") "Opciones con token repetido (se omiten): " JoinNums(dupToks)
    if dupNames.Length
        msg .= (msg ? "`n" : "") "Atajos repetidos (gana el último): " JoinNums(dupNames)
    if wsTrigs.Length
        msg .= (msg ? "`n" : "") "Atajos con espacios (no se pueden escribir): " JoinNums(wsTrigs)
    if msg {
        ; el detalle completo va al log; el TrayTip se corta a ~200 chars
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  Advertencias de atajos.txt:`n" msg "`n", A_ScriptDir "\midword.log", "UTF-8")
        if StrLen(msg) > 200
            msg := SubStr(msg, 1, 200) "…`n(detalle completo en midword.log)"
        TrayTip("Líneas: " msg, "Midword — revisa atajos.txt", "Icon!")
    }
}

JoinNums(arr) {
    s := ""
    for n in arr
        s .= (s ? ", " : "") n
    return s
}

; ==================== Detección de escritura ====================

; ¿la app activa está en apps_excluidas del ini?
AppExcluded() {
    if !APPS_EXCL.Length
        return false
    exe := ""
    try exe := StrLower(WinGetProcessName("A"))
    for a in APPS_EXCL
        if a = exe
            return true
    return false
}

HandleChar(hook, char) {
    global typedBuf, lastIns
    if Ord(char) < 32 {    ; caracteres de control (Ctrl+A, Ctrl+V…): el
        ResetState()       ; contenido del campo pudo cambiar; resetear
        return
    }
    lastIns := ""          ; escribir algo cancela el deshacer con Backspace
    typedBuf .= char
    if StrLen(typedBuf) > 80
        typedBuf := SubStr(typedBuf, -80)
    UpdateSuggestions()
}

HandleKeyDown(hook, vk, sc) {
    global typedBuf, lastIns
    if vk = 0x08 {  ; Backspace
        ; deshacer: un Backspace justo después de expandir borra el texto
        ; insertado y restaura lo que habías escrito (//atajo)
        if lastIns != "" && A_TickCount - lastInsTick < 10000 {
            n := BSLen(lastIns) - 1    ; este Backspace ya borró 1 carácter
            if n > 0
                SendInput("{BS " n "}")
            if lastTypedTxt != ""
                SendInput("{Text}" lastTypedTxt)
            lastIns := ""
            ResetState()
            return
        }
        if GetKeyState("Ctrl", "P") {  ; Ctrl+Backspace borra una palabra:
            ResetState()               ; imposible saber cuánto; resetear
            return
        }
        if typedBuf != ""
            typedBuf := SubStr(typedBuf, 1, -1)
        UpdateSuggestions()
        return
    }
    static resetKeys := Map(0x0D,1, 0x09,1, 0x1B,1, 0x21,1, 0x22,1
        , 0x23,1, 0x24,1, 0x25,1, 0x26,1, 0x27,1, 0x28,1, 0x2E,1)
    if resetKeys.Has(vk) && !suggesting
        ResetState()
}

; minúsculas y sin tildes/ñ para que //numero encuentre "número"
Norm(s) {
    static rep := Map("á","a", "é","e", "í","i", "ó","o", "ú","u", "ü","u", "ñ","n")
    out := ""
    loop parse StrLower(s)
        out .= rep.Has(A_LoopField) ? rep[A_LoopField] : A_LoopField
    return out
}

; ¿pat es subsecuencia de s?  //grc encuentra "gracias"
FuzzyMatch(pat, s) {
    if StrLen(pat) < 2
        return false
    i := 1
    loop parse s {
        if A_LoopField = SubStr(pat, i, 1) {
            i++
            if i > StrLen(pat)
                return true
        }
    }
    return false
}

UseKey(e) {
    return e.kind = "group" ? "grp:" e.name : e.trig
}

; orden estable por frecuencia de uso (más usados primero)
SortByUse(arr) {
    out := []
    for e in arr {
        c := useCount.Get(UseKey(e), 0)
        pos := out.Length + 1
        loop out.Length {
            if useCount.Get(UseKey(out[A_Index]), 0) < c {
                pos := A_Index
                break
            }
        }
        out.InsertAt(pos, e)
    }
    return out
}

UpdateSuggestions() {
    global entries, curTyped, eraseLen
    if AppExcluded() {
        HideSuggestions()
        return
    }
    p := InStr(typedBuf, PREFIX, , -1)  ; última aparición de //
    if !p {
        HideSuggestions()
        return
    }
    ; el prefijo debe estar al inicio o tras un separador: evita que
    ; escribir URLs (https://) o rutas (C://) abra el menú
    if p > 1 && RegExMatch(SubStr(typedBuf, p - 1, 1), "[\w:./\\-]") {
        HideSuggestions()
        return
    }
    typed := SubStr(typedBuf, p + StrLen(PREFIX))
    if typed != "" && RegExMatch(typed, "\s") {
        HideSuggestions()
        return
    }
    ; expansión instantánea (atajos marcados con !)
    if typed != "" && instant.Has(typed) {
        curTyped := typed
        eraseLen := StrLen(PREFIX) + StrLen(typed)
        ExpandTrig(typed)
        return
    }
    ; opción min_caracteres: no abrir el menú hasta tener N letras tras //
    if StrLen(typed) < MIN_CHARS {
        HideSuggestions()
        return
    }
    ; niveles de coincidencia (sin tildes ni mayúsculas): 1) prefijo
    ; (los grupos son UNA fila), 2) dentro del nombre o del texto,
    ; 3) subsecuencia difusa (//grc → gracias)
    tN := Norm(typed)
    m := [], m2 := [], m3 := []
    for entry in order {
        if entry.kind = "group" {
            nameN := Norm(entry.name)
            if typed = "" || InStr(nameN, tN) = 1
                m.Push(entry)                          ; fila única desglosable
            else if InStr(tN, nameN) = 1 {
                for vTrig in entry.variants            ; //con1 filtra con10, con15…
                    if InStr(Norm(vTrig), tN) = 1
                        m.Push({kind: "item", trig: vTrig})
            } else if InStr(nameN, tN) || InStr(Norm(entry.template), tN)
                m2.Push(entry)
            else if FuzzyMatch(tN, nameN)
                m3.Push(entry)
        } else {
            trigN := Norm(entry.trig)
            if typed = "" || InStr(trigN, tN) = 1
                m.Push(entry)
            else if InStr(trigN, tN) || InStr(Norm(shortcuts[entry.trig]), tN)
                m2.Push(entry)
            else if FuzzyMatch(tN, trigN)
                m3.Push(entry)
        }
    }
    if typed != "" {          ; con filtro: los más usados arriba en cada nivel
        m := SortByUse(m)
        m2 := SortByUse(m2)
    }
    for entry in m2
        m.Push(entry)
    for entry in m3
        m.Push(entry)
    if !m.Length {
        HideSuggestions()
        return
    }
    entries := m
    curTyped := typed
    eraseLen := StrLen(PREFIX) + StrLen(typed)
    BuildMenu()
}

; ==================== Menú principal ====================

EntryLabel(entry) {
    return entry.kind = "group" ? PREFIX entry.name "  ▸" : PREFIX entry.trig
}

; entrada mostrada en la fila i del menú (con el scroll aplicado)
EntryAt(i) {
    return entries[viewOff + i]
}

; ancho real del texto en píxeles lógicos de la GUI (GetTextExtentPoint32
; con la fuente indicada, corregido por DPI) — reemplaza el estimado *9
TextWidth(s, fontName := "Consolas", size := 10, weight := 700) {
    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    hpx := -DllCall("MulDiv", "int", size
        , "int", DllCall("GetDeviceCaps", "ptr", hdc, "int", 90), "int", 72)
    hFont := DllCall("CreateFont", "int", hpx, "int", 0, "int", 0, "int", 0
        , "int", weight, "uint", 0, "uint", 0, "uint", 0, "uint", 1
        , "uint", 0, "uint", 0, "uint", 0, "uint", 0, "str", fontName, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", hFont, "ptr")
    sz := Buffer(8, 0)
    DllCall("GetTextExtentPoint32", "ptr", hdc, "str", s, "int", StrLen(s), "ptr", sz)
    w := NumGet(sz, 0, "int")
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("DeleteObject", "ptr", hFont)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    return Round(w * 96 / A_ScreenDPI)
}

DimRange(d) {
    return d.Length > 1 ? d[1].lab "–" d[d.Length].lab : d[1].lab
}

; vista amable de los modos especiales en las vistas previas
PrettyModes(txt) {
    if SubStr(txt, 1, 8) = "teclear:"
        return "⌨ " SubStr(txt, 9)
    if SubStr(txt, 1, 5) = "html:"
        return "✱ " RegExReplace(RegExReplace(SubStr(txt, 6), "i)<br\s*/?>", "  "), "<[^>]+>")
    return txt
}

EntryPreview(entry) {
    if entry.kind = "group" {
        txt := StrReplace(entry.template, "{1}", DimRange(entry.dims[1]))
        if entry.dims.Length > 1
            txt := StrReplace(txt, "{2}", DimRange(entry.dims[2]))
    } else {
        txt := shortcuts[entry.trig]
    }
    if SubStr(txt, 1, 8) = "archivo:" {
        parts := StrSplit(Trim(SubStr(txt, 9)), "|")
        SplitPath(Trim(parts[1]), &fname)
        return "📎 " fname (parts.Length > 1 ? "  (+" (parts.Length - 1) ")" : "")
    }
    txt := PrettyModes(txt)
    txt := StrReplace(txt, "`n", "  ")
    if StrLen(txt) > 56
        txt := SubStr(txt, 1, 56) "…"
    return txt
}

BuildMenu() {
    global sugGui, suggesting, rows, rowByHwnd, selIdx, menuNav
    global menuX, menuY, menuHH, menuRH, menuW, menuTW, menuFooter, menuH, viewOff
    W := 620, HH := 30, RH := 36
    n := Min(entries.Length, MAX_ROWS)
    extra := entries.Length - n
    FH := extra > 0 ? 24 : 0
    H := 1 + HH + n * RH + FH + 1

    maxW := 0
    loop n {
        L := TextWidth(EntryLabel(entries[A_Index]))
        if L > maxW
            maxW := L
    }
    TW := 26 + maxW
    if TW > 200
        TW := 200

    ; si la geometría no cambió, reusar la ventana actualizando los
    ; textos: evita el parpadeo de destruir/crear GUI en cada tecla
    if sugGui && rows.Length = n && menuTW = TW && (menuFooter != 0) = (extra > 0) {
        CloseSub()
        selIdx := 1, menuNav := false, viewOff := 0
        loop n {
            entry := entries[A_Index]
            r := rows[A_Index]
            r.trig.Text := "  " EntryLabel(entry)
            r.prev.Text := EntryPreview(entry)
            StyleRow(A_Index, A_Index = selIdx)
        }
        if menuFooter
            menuFooter.Text := "      sigue escribiendo… (+" extra " atajos más)"
        ShowFullPreview(1)
        if entries[1].kind = "group"
            OpenSub(1)
        return
    }

    CloseSub()
    if sugGui
        sugGui.Destroy()
    rows := [], rowByHwnd := Map()
    selIdx := 1, menuNav := false, viewOff := 0
    menuTW := TW, menuFooter := 0

    sugGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")
    sugGui.BackColor := MNU_BORDER
    sugGui.MarginX := 0, sugGui.MarginY := 0

    ; --- header: título + botón "ver todos" + hints ---
    sugGui.SetFont("s9 c" MNU_ACCENT " w700", "Segoe UI")
    sugGui.Add("Text", "x1 y1 w110 h" HH " Background" MNU_BG " +0x200", "   ●  Midword")
    btn := sugGui.Add("Text", "x111 y1 w90 h" HH " Background" MNU_BG " +0x200", "  ☰ ver todos")
    btn.OnEvent("Click", ShowAllClick)
    sugGui.SetFont("s8 c" MNU_MUTED " w400", "Segoe UI")
    sugGui.Add("Text", "x201 y1 w" (W - 2 - 200) " h" HH " Background" MNU_BG " +0x200 Right",
        "↑↓ elegir  ·  ▸ desglosar  ·  Tab/Enter insertar  ·  Esc   ")

    ; --- filas ---
    loop n {
        i := A_Index
        entry := entries[i]
        y := 1 + HH + (i - 1) * RH
        sel := (i = selIdx)
        rowBg := sel ? MNU_ACC_LITE : MNU_SURFACE

        bar := sugGui.Add("Text", "x1 y" y " w4 h" RH " Background" (sel ? MNU_ACCENT : rowBg))
        sugGui.SetFont("s10 c" MNU_ACC_DARK " w700", "Consolas")
        t := sugGui.Add("Text", "x5 y" y " w" TW " h" RH " Background" rowBg " +0x200 +0x4000", "  " EntryLabel(entry))
        sugGui.SetFont("s10 c" MNU_BODY " w400", "Segoe UI")
        pv := sugGui.Add("Text", "x" (5 + TW) " y" y " w" (W - 1 - 5 - TW) " h" RH " Background" rowBg " +0x200 +0x4000", EntryPreview(entry))

        for ctrl in [bar, t, pv] {
            ctrl.OnEvent("Click", AcceptIndex.Bind(i))
            rowByHwnd[ctrl.Hwnd] := i
        }
        rows.Push({bar: bar, trig: t, prev: pv})
    }

    if extra > 0 {
        sugGui.SetFont("s8 c" MNU_MUTED " w400", "Segoe UI")
        menuFooter := sugGui.Add("Text", "x1 y" (1 + HH + n * RH) " w" (W - 2) " h" FH " Background" MNU_SURF_ALT " +0x200",
            "      sigue escribiendo… (+" extra " atajos más)")
    }

    ; --- posición junto al cursor de texto ---
    x := 0, y := 0
    CoordMode "Caret", "Screen"
    if !CaretGetPos(&x, &y) && !AccCaretPos(&x, &y) {
        CoordMode "Mouse", "Screen"
        MouseGetPos(&x, &y)
    }
    y += 24
    MonWork(x, y, &mL, &mT, &mR, &mB)
    if x > mR - (W + 380)
        x := mR - (W + 380)   ; deja sitio a los submenús
    if x < mL
        x := mL
    if y > mB - (H + 60)
        y -= H + 50
    menuX := x, menuY := y, menuHH := HH, menuRH := RH, menuW := W, menuH := H
    sugGui.Show("x" x " y" y " w" W " h" H " NoActivate")
    RoundWin(sugGui, W, H, 14)
    suggesting := true
    ShowFullPreview(1)
    ; si la primera fila es un grupo, mostrar su desglose de una vez
    if entries[1].kind = "group"
        OpenSub(1)
}

; Caret vía MSAA (OBJID_CARET) para apps donde CaretGetPos falla
; (Chrome/Electron suelen exponerlo cuando activan su accesibilidad).
; Coordenadas de pantalla; false si no hay caret accesible.
AccCaretPos(&x, &y) {
    static IID_IAccessible := "{618736E0-3C3D-11CF-810C-00AA00389B71}"
    try {
        info := Buffer(72, 0)
        NumPut("uint", 72, info, 0)
        if !DllCall("GetGUIThreadInfo", "uint", 0, "ptr", info)
            return false
        hwnd := NumGet(info, 16, "ptr")          ; hwndFocus
        if !hwnd
            hwnd := NumGet(info, 8, "ptr")       ; hwndActive
        if !hwnd
            return false
        iid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "wstr", IID_IAccessible, "ptr", iid)
        pacc := 0
        if DllCall("oleacc\AccessibleObjectFromWindow", "ptr", hwnd
            , "uint", 0xFFFFFFF8, "ptr", iid, "ptr*", &pacc) != 0 || !pacc
            return false
        acc := ComValue(9, pacc)                 ; IDispatch, libera solo
        varChild := Buffer(24, 0)
        NumPut("ushort", 3, varChild, 0)         ; VT_I4
        NumPut("int", 0, varChild, 8)            ; CHILDID_SELF
        l := Buffer(4), t := Buffer(4), w := Buffer(4), h := Buffer(4)
        if ComCall(22, acc, "ptr", l, "ptr", t, "ptr", w, "ptr", h, "ptr", varChild) != 0
            return false
        cx := NumGet(l, "int"), cy := NumGet(t, "int")
        cw := NumGet(w, "int"), ch := NumGet(h, "int")
        if (cx = 0 && cy = 0) || cw > 300 || ch > 200   ; no parece un caret
            return false
        x := cx, y := cy
        return true
    }
    return false
}

; área de trabajo del monitor que contiene el punto x,y (multi-monitor)
MonWork(x, y, &L, &T, &R, &B) {
    L := 0, T := 0, R := A_ScreenWidth, B := A_ScreenHeight
    try loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        if x >= l && x < r && y >= t && y < b {
            L := l, T := t, R := r, B := b
            return
        }
    }
}

; ==================== Submenú nivel 1 ====================

OpenSub(i) {
    global subGui, subEntry, subRows, subByHwnd, subSel, subActive, subForIdx
    global subX, subY, subW
    if subForIdx = i && subGui
        return
    CloseSub()
    entry := EntryAt(i)
    if entry.kind != "group"
        return
    subEntry := entry
    subSel := 0, subActive := false, subForIdx := i

    d1 := entry.dims[1]
    hasL2 := entry.dims.Length > 1
    n := d1.Length, RH := menuRH

    maxLab := 0
    for o in d1
        if TextWidth(o.lab) > maxLab
            maxLab := TextWidth(o.lab)
    LW := 30 + maxLab
    W2 := LW + (hasL2 ? 40 : 130)
    if W2 < 150
        W2 := 150
    H2 := 1 + n * RH + 1

    subGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")
    subGui.BackColor := MNU_BORDER
    subGui.MarginX := 0, subGui.MarginY := 0

    loop n {
        j := A_Index
        y := 1 + (j - 1) * RH
        subGui.SetFont("s10 c" MNU_ACC_DARK " w700", "Consolas")
        o := subGui.Add("Text", "x1 y" y " w" LW " h" RH " Background" MNU_SURFACE " +0x200", "   " d1[j].lab)
        if hasL2 {
            subGui.SetFont("s10 c" MNU_MUTED " w400", "Segoe UI")
            tr := subGui.Add("Text", "x" (1 + LW) " y" y " w" (W2 - 2 - LW) " h" RH " Background" MNU_SURFACE " +0x200", "▸")
        } else {
            subGui.SetFont("s9 c" MNU_MUTED " w400", "Consolas")
            tr := subGui.Add("Text", "x" (1 + LW) " y" y " w" (W2 - 2 - LW) " h" RH " Background" MNU_SURFACE " +0x200", PREFIX entry.variants[j])
        }
        for ctrl in [o, tr] {
            ctrl.OnEvent("Click", AcceptSub.Bind(j))
            subByHwnd[ctrl.Hwnd] := j
        }
        subRows.Push({opt: o, trig: tr})
    }

    x := menuX + menuW - 6
    y := menuY + menuHH + (i - 1) * RH
    MonWork(menuX, menuY, &mL, &mT, &mR, &mB)
    if x + W2 > mR
        x := menuX - W2 + 6
    if y + H2 > mB - 50
        y := mB - 50 - H2
    subX := x, subY := y, subW := W2
    subGui.Show("x" x " y" y " w" W2 " h" H2 " NoActivate")
    RoundWin(subGui, W2, H2, 12)
}

CloseSub() {
    global subGui, subEntry, subRows, subByHwnd, subSel, subActive, subForIdx
    CloseSub2()
    if subGui
        subGui.Destroy()
    subGui := 0, subEntry := 0
    subRows := [], subByHwnd := Map()
    subSel := 0, subActive := false, subForIdx := 0
}

StyleSubRow(j, sel) {
    r := subRows[j]
    bg := sel ? MNU_ACC_LITE : MNU_SURFACE
    r.opt.Opt("Background" bg), r.trig.Opt("Background" bg)
    r.opt.Redraw(), r.trig.Redraw()
}

SetSubSel(j) {
    global subSel
    if j = subSel
        return
    if subSel >= 1 && subSel <= subRows.Length
        StyleSubRow(subSel, false)
    subSel := j
    if j >= 1 && j <= subRows.Length
        StyleSubRow(j, true)
}

; ==================== Submenú nivel 2 ====================

OpenSub2(j) {
    global sub2Gui, sub2Items, sub2Rows, sub2ByHwnd, sub2Sel, sub2Active, sub2ForIdx
    if sub2ForIdx = j && sub2Gui
        return
    CloseSub2()
    if !subEntry || subEntry.dims.Length < 2
        return
    sub2ForIdx := j
    d2 := subEntry.dims[2]
    o1 := subEntry.dims[1][j]
    sub2Items := []
    for o2 in d2
        sub2Items.Push(subEntry.name o1.tok o2.tok)

    n := d2.Length, RH := menuRH
    maxLab := 0
    for o in d2
        if TextWidth(o.lab) > maxLab
            maxLab := TextWidth(o.lab)
    W3 := 60 + maxLab
    if W3 < 130
        W3 := 130
    H3 := 1 + n * RH + 1

    sub2Gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")
    sub2Gui.BackColor := MNU_BORDER
    sub2Gui.MarginX := 0, sub2Gui.MarginY := 0

    loop n {
        k := A_Index
        y := 1 + (k - 1) * RH
        sub2Gui.SetFont("s10 c" MNU_ACC_DARK " w700", "Consolas")
        o := sub2Gui.Add("Text", "x1 y" y " w" (W3 - 2) " h" RH " Background" MNU_SURFACE " +0x200", "   " d2[k].lab)
        o.OnEvent("Click", AcceptSub2.Bind(k))
        sub2ByHwnd[o.Hwnd] := k
        sub2Rows.Push(o)
    }

    x := subX + subW - 6
    y := subY + (j - 1) * RH
    MonWork(subX, subY, &mL, &mT, &mR, &mB)
    if x + W3 > mR
        x := subX - W3 + 6
    if y + H3 > mB - 50
        y := mB - 50 - H3
    sub2Gui.Show("x" x " y" y " w" W3 " h" H3 " NoActivate")
    RoundWin(sub2Gui, W3, H3, 12)
}

; esquinas redondeadas: en Win11 nativas de DWM (con sombra); en
; Win10 la región recortada de siempre (sin sombra)
RoundWin(g, w, h, r) {
    if VerCompare(A_OSVersion, "10.0.22000") >= 0 {
        try {
            DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "int", 33, "int*", 2, "int", 4)
            return
        }
    }
    WinSetRegion("0-0 w" w " h" h " R" r "-" r, g)
}

CloseSub2() {
    global sub2Gui, sub2Items, sub2Rows, sub2ByHwnd, sub2Sel, sub2Active, sub2ForIdx
    if sub2Gui
        sub2Gui.Destroy()
    sub2Gui := 0
    sub2Items := [], sub2Rows := [], sub2ByHwnd := Map()
    sub2Sel := 0, sub2Active := false, sub2ForIdx := 0
}

SetSub2Sel(k) {
    global sub2Sel
    if k = sub2Sel
        return
    if sub2Sel >= 1 && sub2Sel <= sub2Rows.Length {
        sub2Rows[sub2Sel].Opt("Background" MNU_SURFACE)
        sub2Rows[sub2Sel].Redraw()
    }
    sub2Sel := k
    if k >= 1 && k <= sub2Rows.Length {
        sub2Rows[k].Opt("Background" MNU_ACC_LITE)
        sub2Rows[k].Redraw()
    }
}

; ==================== Selección y navegación ====================

StyleRow(i, sel) {
    r := rows[i]
    bg := sel ? MNU_ACC_LITE : MNU_SURFACE
    r.bar.Opt("Background" (sel ? MNU_ACCENT : bg))
    r.trig.Opt("Background" bg)
    r.prev.Opt("Background" bg)
    r.bar.Redraw(), r.trig.Redraw(), r.prev.Redraw()
}

SetSel(i) {
    global selIdx
    if i = selIdx
        return
    if selIdx >= 1 && selIdx <= rows.Length
        StyleRow(selIdx, false)
    selIdx := i
    StyleRow(i, true)
    ShowFullPreview(i)
    if EntryAt(i).kind = "group"
        OpenSub(i)
    else
        CloseSub()
}

SelIsGroup() {
    return entries.Length && selIdx >= 1 && selIdx <= rows.Length
        && viewOff + selIdx <= entries.Length && EntryAt(selIdx).kind = "group"
}

SubHasL2() {
    return subEntry && subEntry.dims.Length > 1
}

CanGoRight() {
    return (!subActive && SelIsGroup()) || (subActive && !sub2Active && SubHasL2())
}

GoRight() {
    global subActive, sub2Active, menuNav := true
    if !subActive {
        if !subGui
            OpenSub(selIdx)
        subActive := true
        SetSubSel(1)
        if SubHasL2()
            OpenSub2(1)
        return
    }
    if SubHasL2() {
        OpenSub2(subSel >= 1 ? subSel : 1)
        sub2Active := true
        SetSub2Sel(1)
    }
}

GoLeft() {
    global subActive, sub2Active
    if sub2Active {
        sub2Active := false
        SetSub2Sel(0)
        return
    }
    subActive := false
    SetSubSel(0)
    CloseSub2()
}

NavKey(d) {
    global viewOff, menuNav := true
    if sub2Active {
        k := sub2Sel + d
        if k < 1
            k := sub2Rows.Length
        else if k > sub2Rows.Length
            k := 1
        SetSub2Sel(k)
        return
    }
    if subActive {
        j := subSel + d
        if j < 1
            j := subRows.Length
        else if j > subRows.Length
            j := 1
        SetSubSel(j)
        if SubHasL2()
            OpenSub2(j)
        return
    }
    i := selIdx + d
    if i < 1 {
        if viewOff > 0 {                      ; scroll hacia arriba
            viewOff--
            ScrollSync(1)
        } else {                              ; tope absoluto → ir al final
            viewOff := Max(0, entries.Length - rows.Length)
            ScrollSync(Min(rows.Length, entries.Length))
        }
        return
    }
    if i > rows.Length {
        if viewOff + rows.Length < entries.Length {   ; scroll hacia abajo
            viewOff++
            ScrollSync(rows.Length)
        } else {                              ; fin absoluto → volver arriba
            viewOff := 0
            ScrollSync(1)
        }
        return
    }
    SetSel(i)
}

; tras un scroll: repintar las filas con la ventana desplazada y
; seleccionar newSel aunque el número de fila no haya cambiado
ScrollSync(newSel) {
    global selIdx, viewOff
    RefreshMenuRows()
    CloseSub()
    if selIdx >= 1 && selIdx <= rows.Length && selIdx != newSel
        StyleRow(selIdx, false)
    selIdx := newSel
    StyleRow(newSel, true)
    ShowFullPreview(newSel)
    if EntryAt(newSel).kind = "group"
        OpenSub(newSel)
}

RefreshMenuRows() {
    loop rows.Length {
        entry := EntryAt(A_Index)
        r := rows[A_Index]
        r.trig.Text := "  " EntryLabel(entry)
        r.prev.Text := EntryPreview(entry)
    }
    if menuFooter {
        rem := entries.Length - viewOff - rows.Length
        menuFooter.Text := rem > 0
            ? "      sigue escribiendo… (+" rem " atajos más)"
            : "      (fin de la lista)"
    }
}

; tooltip con el texto completo del atajo seleccionado si la vista
; previa de la fila no alcanza (textos largos o multilínea)
ShowFullPreview(i) {
    if viewOff + i > entries.Length {
        ToolTip(, , , 20)
        return
    }
    entry := EntryAt(i)
    txt := entry.kind = "group" ? entry.template : shortcuts[entry.trig]
    txt := PrettyModes(txt)
    if SubStr(txt, 1, 8) = "archivo:" || (StrLen(txt) <= 56 && !InStr(txt, "`n")) {
        ToolTip(, , , 20)
        return
    }
    if StrLen(txt) > 400
        txt := SubStr(txt, 1, 400) "…"
    ToolTip(txt, menuX + 6, menuY + menuH + 10, 20)
}

; sigue el mouse sin polling: WM_MOUSEMOVE llega al control bajo el
; cursor; pasar sobre una fila la selecciona y desglosa grupos
OnMouseMove(wParam, lParam, msg, hwnd) {
    global subActive, sub2Active, menuNav
    if !suggesting
        return
    if rowByHwnd.Has(hwnd) {
        menuNav := true
        SetSel(rowByHwnd[hwnd])
        if subActive || sub2Active {
            subActive := false, sub2Active := false
            SetSubSel(0)
        }
    } else if subByHwnd.Has(hwnd) {
        j := subByHwnd[hwnd]
        subActive := true, menuNav := true
        if j != subSel {
            SetSubSel(j)
            if SubHasL2()
                OpenSub2(j)
            else
                CloseSub2()
        }
    } else if sub2ByHwnd.Has(hwnd) {
        sub2Active := true, menuNav := true
        SetSub2Sel(sub2ByHwnd[hwnd])
    }
}

; ==================== Aceptar e insertar ====================

AcceptIndex(idx, *) {
    if idx > rows.Length || viewOff + idx > entries.Length
        return
    if EntryAt(idx).kind = "group" {
        SetSel(idx)
        GoRight()
    } else
        ExpandTrig(EntryAt(idx).trig)
}

AcceptSub(j, *) {
    global subActive, sub2Active
    if !subEntry
        return
    if SubHasL2() {
        subActive := true
        SetSubSel(j)
        OpenSub2(j)
        sub2Active := true
        SetSub2Sel(1)
    } else if j >= 1 && j <= subEntry.variants.Length
        ExpandTrig(subEntry.variants[j])
}

AcceptSub2(k, *) {
    if k >= 1 && k <= sub2Items.Length
        ExpandTrig(sub2Items[k])
}

AcceptKey() {
    if !entries.Length
        return
    if sub2Active && sub2Sel >= 1 {
        ExpandTrig(sub2Items[sub2Sel])
        return
    }
    if subActive && subSel >= 1 {
        if SubHasL2() {
            GoRight()
            return
        }
        ExpandTrig(subEntry.variants[subSel])
        return
    }
    if SelIsGroup() {
        GoRight()
        return
    }
    ExpandTrig(EntryAt(selIdx).trig)
}

; Borra lo escrito (//xxx) y lo reemplaza por el texto del atajo
ExpandTrig(trig) {
    global typedBuf, curTyped, lastIns, lastTypedTxt, lastInsTick, expandCanceled
    if !shortcuts.Has(trig) {   ; pudo desaparecer tras una recarga externa
        ResetState()
        return
    }
    txt := shortcuts[trig]
    grpName := subEntry ? subEntry.name : ""   ; antes de cerrar los submenús
    HideSuggestions()
    if eraseLen > 0
        SendInput("{BS " eraseLen "}")
    Sleep 50
    lastIns := InsertText(txt)
    if expandCanceled {          ; canceló un {input:…}: devolver lo escrito
        expandCanceled := false
        lastIns := ""
        if eraseLen > 0
            SendText(PREFIX curTyped)
        typedBuf := "", curTyped := ""
        return
    }
    lastTypedTxt := eraseLen > 0 ? PREFIX curTyped : ""
    lastInsTick := A_TickCount
    ; contador de uso: rankea las próximas sugerencias
    useCount[trig] := useCount.Get(trig, 0) + 1
    try IniWrite(useCount[trig], USE_FILE, "uso", trig)
    if grpName != "" {   ; venía del desglose: acredita también al grupo
        gk := "grp:" grpName
        useCount[gk] := useCount.Get(gk, 0) + 1
        try IniWrite(useCount[gk], USE_FILE, "uso", gk)
    }
    if SONIDO
        SoundBeep(1400, 60)
    typedBuf := ""
    curTyped := ""
}

; nº de pulsaciones de Backspace para borrar s (por code point: los
; emojis ocupan 2 unidades UTF-16 pero se borran con UN Backspace)
BSLen(s) {
    return StrLen(RegExReplace(s, "s).", "·"))
}

; Pone uno o varios archivos en el portapapeles como CF_HDROP (igual
; que Ctrl+C sobre archivos en el Explorador): WhatsApp/Telegram los
; adjuntan, Word/Docs insertan la imagen, Gmail los adjunta.
SetClipboardFiles(paths) {                 ; paths: Array de rutas
    chars := 1                             ; NUL final de la lista
    for f in paths
        chars += StrLen(f) + 1             ; cada ruta + su NUL
    bytes := 20 + chars * 2                ; DROPFILES (20) + lista UTF-16
    hMem := DllCall("GlobalAlloc", "uint", 0x42, "uptr", bytes, "ptr")
    p := DllCall("GlobalLock", "ptr", hMem, "ptr")
    NumPut("uint", 20, p, 0)               ; pFiles = sizeof(DROPFILES)
    NumPut("int", 1, p, 16)                ; fWide = TRUE (UTF-16)
    off := 20
    for f in paths {
        StrPut(f, p + off, "UTF-16")
        off += (StrLen(f) + 1) * 2
    }                                      ; el doble NUL final ya es 0 (ZEROINIT)
    DllCall("GlobalUnlock", "ptr", hMem)
    ; reintentar: otro proceso (gestores de portapapeles) puede tenerlo abierto
    opened := false
    loop 5 {
        if DllCall("OpenClipboard", "ptr", A_ScriptHwnd) {
            opened := true
            break
        }
        Sleep 30
    }
    if !opened {
        DllCall("GlobalFree", "ptr", hMem)
        return false
    }
    DllCall("EmptyClipboard")
    ok := DllCall("SetClipboardData", "uint", 15, "ptr", hMem, "ptr")  ; CF_HDROP
    DllCall("CloseClipboard")
    if !ok   ; si falló, el sistema no tomó posesión de la memoria
        DllCall("GlobalFree", "ptr", hMem)
    return !!ok
}

; Pone HTML ("HTML Format") + texto plano en el portapapeles, para
; que Word/Gmail/Docs peguen con formato y el resto pegue el plano
SetClipboardHTML(html, plain) {
    static cfHtml := DllCall("RegisterClipboardFormat", "str", "HTML Format", "uint")
    mk(sh, eh, sf, ef) => "Version:0.9`r`nStartHTML:" Format("{:010}", sh)
        . "`r`nEndHTML:" Format("{:010}", eh) "`r`nStartFragment:" Format("{:010}", sf)
        . "`r`nEndFragment:" Format("{:010}", ef) "`r`n"
    pre := "<html><body><!--StartFragment-->"
    post := "<!--EndFragment--></body></html>"
    hdrLen := StrPut(mk(0, 0, 0, 0), "UTF-8") - 1
    startFrag := hdrLen + StrPut(pre, "UTF-8") - 1
    endFrag := startFrag + StrPut(html, "UTF-8") - 1
    endHtml := endFrag + StrPut(post, "UTF-8") - 1
    data := mk(hdrLen, endHtml, startFrag, endFrag) pre html post
    n := StrPut(data, "UTF-8") - 1
    hMem := DllCall("GlobalAlloc", "uint", 0x42, "uptr", n + 1, "ptr")
    p := DllCall("GlobalLock", "ptr", hMem, "ptr")
    StrPut(data, p, n + 1, "UTF-8")
    DllCall("GlobalUnlock", "ptr", hMem)
    hTxt := DllCall("GlobalAlloc", "uint", 0x42, "uptr", (StrLen(plain) + 1) * 2, "ptr")
    p2 := DllCall("GlobalLock", "ptr", hTxt, "ptr")
    StrPut(plain, p2, "UTF-16")
    DllCall("GlobalUnlock", "ptr", hTxt)
    opened := false
    loop 5 {
        if DllCall("OpenClipboard", "ptr", A_ScriptHwnd) {
            opened := true
            break
        }
        Sleep 30
    }
    if !opened {
        DllCall("GlobalFree", "ptr", hMem), DllCall("GlobalFree", "ptr", hTxt)
        return false
    }
    DllCall("EmptyClipboard")
    ok1 := DllCall("SetClipboardData", "uint", cfHtml, "ptr", hMem, "ptr")
    ok2 := DllCall("SetClipboardData", "uint", 13, "ptr", hTxt, "ptr")   ; CF_UNICODETEXT
    DllCall("CloseClipboard")
    if !ok1
        DllCall("GlobalFree", "ptr", hMem)
    if !ok2
        DllCall("GlobalFree", "ptr", hTxt)
    return !!(ok1 && ok2)
}

; Inserta un atajo de archivo (imagen, video, PDF…); admite varios
; separados por |:  pack=archivo:C:\a.png|C:\b.pdf
InsertFile(pathSpec) {
    paths := [], missing := ""
    for f in StrSplit(pathSpec, "|") {
        f := Trim(f)
        if f = ""
            continue
        if FileExist(f)
            paths.Push(f)
        else
            missing .= (missing ? "`n" : "") f
    }
    if missing != ""
        TrayTip("No se encontró:`n" missing, "Midword", "Icon!")
    if !paths.Length
        return
    saved := ClipboardAll()
    if !SetClipboardFiles(paths) {
        A_Clipboard := saved
        return
    }
    Send("^v")
    Sleep DELAY_ARCHIVO   ; adjuntar un archivo tarda más que pegar texto
    A_Clipboard := saved
}

; Inserta pegando desde el portapapeles: instantáneo, soporta
; textos largos y los saltos de línea NO envían el mensaje en
; WhatsApp/Telegram. Restaura lo que tenías copiado.
; Resuelve las variables ({fecha…}, {$var}, {portapapeles}, {input:…})
; sobre &txt. Deja \{ convertida en Chr(2): el llamador la restaura.
; Devuelve false si el usuario canceló un {input}.
ResolveVars(&txt) {
    txt := StrReplace(txt, "\{", Chr(2))   ; \{ = llave literal, sin reemplazo
    txt := StrReplace(txt, "{fecha_larga}", FormatTime(, "d 'de' MMMM 'de' yyyy"))
    ; {fecha+7} / {fecha-2} → fecha desplazada N días (plazos de entrega)
    while RegExMatch(txt, "\{fecha([+-]\d+)\}", &mf)
        txt := StrReplace(txt, mf[0], FormatTime(DateAdd(A_Now, Integer(mf[1]), "Days"), "dd/MM/yyyy"))
    txt := StrReplace(txt, "{fecha}", FormatTime(, "dd/MM/yyyy"))
    txt := StrReplace(txt, "{hora}", FormatTime(, "HH:mm"))
    txt := StrReplace(txt, "{dia}", FormatTime(, "dddd"))
    ; {$var} → variables de usuario definidas como  $var=valor
    while RegExMatch(txt, "\{\$([^}]+)\}", &mu)
        txt := StrReplace(txt, mu[0], userVars.Get(Trim(mu[1]), ""))
    ; {portapapeles} → lo que tengas copiado (antes de tocar el clipboard)
    txt := StrReplace(txt, "{portapapeles}", A_Clipboard)
    ; {input:Pregunta} → mini-diálogo al expandir; cancelar aborta
    hadInput := false
    while RegExMatch(txt, "\{input:([^}]*)\}", &mi) {
        ib := InputBox(mi[1], "Midword", "w340 h130")
        if ib.Result != "OK"
            return false
        txt := StrReplace(txt, mi[0], ib.Value)
        hadInput := true
    }
    if hadInput
        Sleep 200   ; dar tiempo a que el foco vuelva a la app
    return true
}

; Devuelve el texto realmente pegado ("" si no se pudo pegar, fue un
; archivo o usó {cursor}): lo usa el deshacer con Backspace.
InsertText(txt) {
    ; atajos de archivo:  miatajo=archivo:C:\ruta\imagen.png
    if SubStr(txt, 1, 8) = "archivo:" {
        InsertFile(Trim(SubStr(txt, 9)))
        return ""
    }
    if !ResolveVars(&txt) {
        global expandCanceled := true
        return ""
    }
    txt := StrReplace(txt, Chr(2), "{")
    ; teclear: escribe tecla por tecla (para apps que bloquean Ctrl+V)
    if SubStr(txt, 1, 8) = "teclear:" {
        t := StrReplace(SubStr(txt, 9), "{cursor}", "")
        SendText(t)
        return t
    }
    ; html: pega con formato (negritas, listas) en Word/Gmail/Docs
    if SubStr(txt, 1, 5) = "html:" {
        html := SubStr(txt, 6)
        plain := RegExReplace(RegExReplace(html, "i)<br\s*/?>", "`n"), "<[^>]+>")
        saved := ClipboardAll()
        if !SetClipboardHTML(html, plain) {
            A_Clipboard := saved
            return ""
        }
        Send("^v")
        Sleep DELAY_PEGAR
        A_Clipboard := saved
        return ""   ; sin deshacer: el largo pegado depende de la app
    }
    back := 0
    cp := InStr(txt, "{cursor}")
    if cp {
        ; contar por code points: un emoji tras {cursor} = UNA flecha
        back := BSLen(SubStr(txt, cp + StrLen("{cursor}")))
        txt := StrReplace(txt, "{cursor}", "")
    }
    saved := ClipboardAll()
    A_Clipboard := txt
    pasted := false
    if ClipWait(1) {
        Send("^v")
        Sleep DELAY_PEGAR   ; dar tiempo a que la app procese el pegado
        pasted := true
    }
    A_Clipboard := saved
    if back > 0 {
        Send("{Left " back "}")
        return ""   ; con {cursor} el caret ya no queda al final: sin deshacer
    }
    return pasted ? txt : ""
}

; ==================== Mostrar todo / cerrar ====================

ShowAllClick(*) {
    global entries
    entries := []
    for entry in order
        entries.Push(entry)
    BuildMenu()
}

ShowAllFromTray(*) {
    global entries, curTyped, eraseLen, typedBuf
    typedBuf := "", curTyped := "", eraseLen := 0
    entries := []
    for entry in order
        entries.Push(entry)
    if entries.Length
        BuildMenu()
}

HideSuggestions() {
    global suggesting, menuNav, sugGui, rows, rowByHwnd, entries, menuFooter, viewOff
    menuNav := false, menuFooter := 0, viewOff := 0
    ToolTip(, , , 20)
    CloseSub()
    suggesting := false
    rows := [], rowByHwnd := Map(), entries := []
    if sugGui {
        sugGui.Destroy()
        sugGui := 0
    }
}

ResetState() {
    global typedBuf, curTyped, lastIns
    typedBuf := ""
    curTyped := ""
    lastIns := ""   ; clic o navegación: el caret pudo moverse, sin deshacer
    HideSuggestions()
}

; ==================== Gestor de atajos ====================
; Ventana para crear/editar atajos sin tocar la sintaxis del archivo.
; Maquetación calcada de BiPe Alerta: hero oscuro con el logo,
; tarjetas blancas redondeadas sobre fondo crema y botones pill.

; esquinas redondeadas para un control (las "cards" y "pills" de la app)
RoundCtrl(ctrl, w, h, r) {
    DllCall("SetWindowRgn", "ptr", ctrl.Hwnd
        , "ptr", DllCall("CreateRoundRectRgn", "int", 0, "int", 0
            , "int", w + 1, "int", h + 1, "int", r, "int", r, "ptr")
        , "int", 1)
}

; botón estilo pill (corners 100dp en la app)
Pill(g, x, y, w, h, txt, bg, fg, cb, fontOpts := "s10 w700") {
    g.SetFont(fontOpts " c" fg, "Segoe UI")
    ctrl := g.Add("Text", "x" x " y" y " w" w " h" h " Center +0x200 Background" bg, txt)
    RoundCtrl(ctrl, w, h, h)
    ctrl.OnEvent("Click", cb)
    return ctrl
}

OpenManager(*) {
    global mgrGui, mgrLV, mgrSearch, mgrName, mgrInst, mgrText
    global mgrL1, mgrL2, mgrPrev, mgrCount, mgrCardL, mgrCardR, mgrPills, mgrDirty
    if mgrGui {
        RefreshMgrList()
        mgrGui.Show()
        return
    }
    ; redimensionable solo en alto (ancho fijo 800): crece la lista
    mgrGui := Gui("+Resize -MaximizeBox +MinSize800x516 +MaxSize800x", "Midword")
    mgrGui.BackColor := CLR_BG
    mgrGui.OnEvent("Close", MgrTryClose)
    mgrGui.OnEvent("Escape", MgrTryClose)
    mgrGui.OnEvent("Size", MgrSize)
    ; barra de título oscura, a juego con el hero
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", mgrGui.Hwnd, "int", 20, "int*", 1, "int", 4)

    ; ===== hero oscuro (bg_hero_gradient de la app) =====
    hero := mgrGui.Add("Text", "x12 y10 w776 h86 Background" CLR_TEXT)
    RoundCtrl(hero, 776, 86, 28)
    if FileExist(A_ScriptDir "\logo_hero.png")
        mgrGui.Add("Picture", "x36 y26 w34 h34", A_ScriptDir "\logo_hero.png")
    mgrGui.SetFont("s14 w700 cFFFFFF", "Segoe UI")
    mgrGui.Add("Text", "x80 y24 w110 h28 Background" CLR_TEXT, "Midword")
    mgrGui.SetFont("s14 w400 c" CLR_ONDARK, "Segoe UI")
    mgrGui.Add("Text", "x176 y23 w12 h28 Background" CLR_TEXT, "|")
    mgrGui.SetFont("s8 w700 c" CLR_ACCENT, "Segoe UI")
    mgrGui.Add("Text", "x82 y57 w12 h14 Background" CLR_TEXT, "●")
    mgrGui.SetFont("s8 w700 cFFFFFF", "Segoe UI")
    mgrGui.Add("Text", "x96 y57 w180 h14 Background" CLR_TEXT, "GESTOR DE ATAJOS")
    mgrGui.SetFont("s9 w400 c" CLR_ONDARK, "Segoe UI")
    mgrCount := mgrGui.Add("Text", "x540 y54 w224 h20 Background" CLR_TEXT " Right", "")

    ; ===== tarjeta izquierda: buscador + lista =====
    mgrCardL := mgrGui.Add("Text", "x12 y106 w330 h354 Background" CLR_SURFACE)
    RoundCtrl(mgrCardL, 330, 354, 24)
    mgrGui.SetFont("s9 w400 c" CLR_MUTED, "Segoe UI")
    mgrGui.Add("Text", "x30 y120 w200 Background" CLR_SURFACE, "Buscar atajo:")
    Pill(mgrGui, 256, 116, 30, 20, "▲", CLR_ACC_LITE, CLR_ACC_DARK, MgrMove.Bind(-1), "s8 w700")
    Pill(mgrGui, 292, 116, 30, 20, "▼", CLR_ACC_LITE, CLR_ACC_DARK, MgrMove.Bind(1), "s8 w700")
    mgrGui.SetFont("s10 w400 c" CLR_TEXT, "Segoe UI")
    mgrSearch := mgrGui.Add("Edit", "x30 y138 w294 Background" CLR_SURF_ALT)
    mgrSearch.OnEvent("Change", (*) => RefreshMgrList())
    mgrLV := mgrGui.Add("ListView", "x30 y172 w294 h270 -E0x200 Background" CLR_SURFACE, ["Atajo", "Texto"])
    mgrLV.OnEvent("ItemSelect", MgrItemSelect)
    mgrLV.ModifyCol(1, 92), mgrLV.ModifyCol(2, 178)

    ; ===== tarjeta derecha: formulario =====
    mgrCardR := mgrGui.Add("Text", "x354 y106 w434 h354 Background" CLR_SURFACE)
    RoundCtrl(mgrCardR, 434, 354, 24)
    X2 := 372
    mgrGui.SetFont("s9 w400 c" CLR_MUTED, "Segoe UI")
    mgrGui.Add("Text", "x" X2 " y118 w220 Background" CLR_SURFACE, "Nombre (lo escribirás como " PREFIX "nombre):")
    mgrGui.SetFont("s10 w400 c" CLR_TEXT, "Segoe UI")
    mgrName := mgrGui.Add("Edit", "x" X2 " y136 w180 Background" CLR_SURF_ALT)
    mgrName.OnEvent("Change", (*) => (mgrDirty := true, UpdateMgrPreview()))
    mgrGui.SetFont("s9 w400 c" CLR_BODY, "Segoe UI")
    mgrInst := mgrGui.Add("Checkbox", "x" (X2 + 196) " y139 w200 Background" CLR_SURFACE, "Instantáneo (sin Tab)")
    mgrInst.OnEvent("Click", (*) => (mgrDirty := true, UpdateMgrPreview()))

    mgrGui.SetFont("s9 w400 c" CLR_MUTED, "Segoe UI")
    mgrGui.Add("Text", "x" X2 " y168 w300 Background" CLR_SURFACE, "Texto a insertar (Enter = salto de línea):")
    Pill(mgrGui, X2 + 300, 160, 104, 26, "📎 archivo…", CLR_ACC_LITE, CLR_ACC_DARK, PickFile, "s9 w600")
    mgrGui.SetFont("s10 w400 c" CLR_TEXT, "Segoe UI")
    mgrText := mgrGui.Add("Edit", "x" X2 " y186 w398 h78 Multi WantReturn VScroll Background" CLR_SURF_ALT)
    mgrText.OnEvent("Change", (*) => (mgrDirty := true, UpdateMgrPreview()))

    ; variables como mini-pills verdes
    vx := X2
    for v in ["{fecha}", "{hora}", "{dia}", "{fecha_larga}", "{cursor}", "{1}", "{2}"] {
        bw := 14 + StrLen(v) * 6
        Pill(mgrGui, vx, 272, bw, 20, v, CLR_ACC_LITE, CLR_ACC_DARK, InsertVar.Bind(v), "s8 w600")
        vx += bw + 5
    }

    mgrGui.SetFont("s9 w400 c" CLR_MUTED, "Segoe UI")
    mgrGui.Add("Text", "x" X2 " y300 w192 h28 Background" CLR_SURFACE, "Desglose nivel 1 — una opción`npor línea; en el texto va {1}:")
    mgrGui.Add("Text", "x" (X2 + 206) " y300 w192 h28 Background" CLR_SURFACE, "Desglose nivel 2 — se abre tras`nel nivel 1; en el texto va {2}:")
    mgrGui.SetFont("s10 w400 c" CLR_TEXT, "Segoe UI")
    mgrL1 := mgrGui.Add("Edit", "x" X2 " y332 w192 h58 Multi WantReturn VScroll Background" CLR_SURF_ALT)
    mgrL1.OnEvent("Change", (*) => (mgrDirty := true, UpdateMgrPreview()))
    mgrL2 := mgrGui.Add("Edit", "x" (X2 + 206) " y332 w192 h58 Multi WantReturn VScroll Background" CLR_SURF_ALT)
    mgrL2.OnEvent("Change", (*) => (mgrDirty := true, UpdateMgrPreview()))

    mgrGui.SetFont("s8 w700 c" CLR_ACCENT, "Segoe UI")
    mgrGui.Add("Text", "x" X2 " y398 w200 Background" CLR_SURFACE, "VISTA PREVIA")
    Pill(mgrGui, X2 + 328, 392, 76, 20, "▶ Probar", CLR_ACC_LITE, CLR_ACC_DARK, MgrTest, "s8 w600")
    mgrGui.SetFont("s9 w400 c" CLR_BODY, "Segoe UI")
    mgrPrev := mgrGui.Add("Text", "x" X2 " y414 w398 h38 Background" CLR_ACC_LITE, "")
    RoundCtrl(mgrPrev, 398, 38, 12)

    ; ===== botonera pill =====
    mgrPills := []
    mgrPills.Push(Pill(mgrGui, 12, 472, 90, 30, "+ Nuevo", CLR_ACC_LITE, CLR_ACC_DARK, MgrNewBtn))
    mgrPills.Push(Pill(mgrGui, 110, 472, 90, 30, "Duplicar", CLR_ACC_LITE, CLR_ACC_DARK, MgrDup))
    mgrPills.Push(Pill(mgrGui, 208, 472, 90, 30, "Eliminar", CLR_RED_LITE, CLR_RED, MgrDelete))
    mgrPills.Push(Pill(mgrGui, 306, 472, 122, 30, "Importar IA", CLR_ACC_LITE, CLR_ACC_DARK, MgrImport))
    mgrPills.Push(Pill(mgrGui, 436, 472, 96, 30, "Exportar", CLR_ACC_LITE, CLR_ACC_DARK, MgrExport))
    mgrPills.Push(Pill(mgrGui, 540, 472, 116, 30, "Abrir archivo", CLR_ACC_LITE, CLR_ACC_DARK, EditConfig))
    mgrPills.Push(Pill(mgrGui, 664, 472, 124, 30, "Guardar", CLR_ACCENT, "FFFFFF", MgrSave))

    RefreshMgrList()
    MgrNew()
    mgrGui.Show("w800 h516")
}

InsertVar(v, *) {
    DllCall("user32\SendMessageW", "ptr", mgrText.Hwnd, "uint", 0xC2, "ptr", 1, "wstr", v)
    UpdateMgrPreview()
}

; cerrar (X o Esc) confirmando si hay cambios sin guardar
MgrTryClose(*) {
    if MgrDirtyOk()
        mgrGui.Hide()
    return 1
}

MgrDirtyOk() {
    global mgrDirty
    static lastNoTick := 0
    if !mgrDirty
        return true
    ; una multi-selección dispara ItemSelect por cada fila: si acaba de
    ; responder "No", no volver a preguntar en la misma ráfaga
    if A_TickCount - lastNoTick < 800
        return false
    if MsgBox("Tienes cambios sin guardar en el formulario.`n`n¿Descartarlos?", "Midword", "YesNo Icon?") = "Yes" {
        mgrDirty := false
        return true
    }
    lastNoTick := A_TickCount
    return false
}

; resize vertical: crecen las tarjetas y la lista; los botones bajan
MgrSize(g, minMax, w, h) {
    global
    if minMax = -1 || !mgrLV
        return
    dh := Max(0, h - 516)
    mgrCardL.Move(, , , 354 + dh), RoundCtrl(mgrCardL, 330, 354 + dh, 24)
    mgrCardR.Move(, , , 354 + dh), RoundCtrl(mgrCardR, 434, 354 + dh, 24)
    mgrLV.Move(, , , 270 + dh)
    for p in mgrPills
        p.Move(, 472 + dh)
}

MgrNewBtn(*) {
    if MgrDirtyOk()
        MgrNew()
}

; exporta atajos.txt (para llevarlo a otra PC; allá se usa Importar)
MgrExport(*) {
    f := FileSelect("S16", A_ScriptDir "\atajos-midword.txt", "Exportar atajos a…", "Texto (*.txt)")
    if f = ""
        return
    try {
        FileCopy(CONFIG, f, 1)
        TrayTip("Atajos exportados a:`n" f, "Midword")
    } catch as e {
        MsgBox("No se pudo exportar: " e.Message, "Midword", "Icon!")
    }
}

RefreshMgrList() {
    global mgrRows
    if !mgrGui
        return
    if mgrCount
        mgrCount.Text := shortcuts.Count " frases  ·  " order.Length " atajos"
    filter := Norm(mgrSearch.Value)   ; sin tildes, como el menú
    mgrLV.Delete()
    mgrRows := []
    lastSec := ""
    for entry in order {
        label := EntryLabel(entry)
        prev := EntryPreview(entry)
        if filter = "" || InStr(Norm(label), filter) || InStr(Norm(prev), filter) {
            ; separador de sección (solo sin filtro, para no estorbar)
            if filter = "" && entry.sec != "" && entry.sec != lastSec {
                mgrLV.Add(, "── " entry.sec, "")
                mgrRows.Push({kind: "sec", name: entry.sec})
            }
            lastSec := entry.sec
            mgrLV.Add(, label, prev)
            mgrRows.Push(entry)
        }
    }
}

MgrItemSelect(lv, item, selected) {
    global mgrNewSec
    if !(selected && item >= 1 && item <= mgrRows.Length)
        return
    e := mgrRows[item]
    if !MgrDirtyOk()
        return
    if e.kind = "sec" {          ; clic en una sección: los atajos nuevos
        MgrNew()                 ; se guardarán al final de esa sección
        mgrNewSec := e.name
        return
    }
    LoadEntryToForm(e)
}

LoadEntryToForm(entry) {
    global mgrSelLine, mgrSelRaw, mgrNewSec
    mgrSelLine := entry.line
    mgrSelRaw := (entry.line >= 1 && entry.line <= rawLines.Length) ? rawLines[entry.line] : ""
    mgrNewSec := entry.sec
    if entry.kind = "group" {
        mgrName.Value := entry.name
        mgrText.Value := StrReplace(entry.template, "`n", "`r`n")
        mgrL1.Value := LevelToText(entry.dims[1])
        mgrL2.Value := entry.dims.Length > 1 ? LevelToText(entry.dims[2]) : ""
        mgrInst.Value := instant.Has(entry.variants[1]) ? 1 : 0
    } else {
        mgrName.Value := entry.trig
        mgrText.Value := StrReplace(shortcuts[entry.trig], "`n", "`r`n")
        mgrL1.Value := "", mgrL2.Value := ""
        mgrInst.Value := instant.Has(entry.trig) ? 1 : 0
    }
    UpdateMgrPreview()
    global mgrDirty := false   ; lo recién cargado no cuenta como cambio
}

; token automático a partir de la etiqueta: "APA 7" -> apa7, "10 páginas" -> 10
AutoTok(lab) {
    static rep := Map("á","a","é","e","í","i","ó","o","ú","u","ñ","n","ü","u")
    out := ""
    loop parse StrLower(lab) {
        ch := A_LoopField
        if rep.Has(ch)
            ch := rep[ch]
        if RegExMatch(ch, "[a-z0-9]")
            out .= ch
    }
    if RegExMatch(out, "^\d+", &mn)
        return mn[0]
    return SubStr(out, 1, 10)
}

; texto del cuadro de nivel -> [{tok, lab}]; acepta "Etiqueta" o "token: Etiqueta"
ParseLevel(s) {
    arr := []
    for ln in StrSplit(s, "`n", "`r") {
        ln := Trim(ln)
        if ln = ""
            continue
        c := InStr(ln, ":")
        tok := c ? Trim(SubStr(ln, 1, c - 1)) : AutoTok(ln)
        lab := c ? Trim(SubStr(ln, c + 1)) : ln
        if tok != "" && lab != ""
            arr.Push({tok: tok, lab: lab})
    }
    return arr
}

LevelToText(d) {
    s := ""
    for o in d
        s .= (o.tok = AutoTok(o.lab) ? o.lab : o.tok ": " o.lab) "`r`n"
    return s
}

SerializeAtajo(name, isInstant, txt, l1, l2) {
    t := name
    for lvl in [l1, l2] {
        if !lvl.Length
            continue
        s := ""
        for o in lvl
            s .= (s ? "|" : "") (o.tok = AutoTok(o.lab) ? o.lab : o.tok ":" o.lab)
        t .= "[" s "]"
    }
    if isInstant
        t .= "!"
    txt := StrReplace(txt, "\n", "\\n")   ; "\n" literal escrito por el usuario
    txt := StrReplace(txt, A_Tab, "\t")
    return t "=" StrReplace(txt, "`n", "\n")
}

UpdateMgrPreview() {
    if !mgrGui
        return
    name := Trim(mgrName.Value)
    l1 := ParseLevel(mgrL1.Value), l2 := ParseLevel(mgrL2.Value)
    txt := StrReplace(mgrText.Value, "`r`n", "`n")
    head := PREFIX (name != "" ? name : "…")
    if l1.Length {
        head .= "  ▸ " l1[1].lab
        txt := StrReplace(txt, "{1}", l1[1].lab)
        if l2.Length {
            head .= "  ▸ " l2[1].lab
            txt := StrReplace(txt, "{2}", l2[1].lab)
        }
    }
    if SubStr(txt, 1, 8) = "archivo:" {
        pparts := StrSplit(Trim(SubStr(txt, 9)), "|")
        SplitPath(Trim(pparts[1]), &pfn)
        txt := "📎 " pfn (pparts.Length > 1 ? " (+" (pparts.Length - 1) " más)" : "") " (se adjunta)"
    }
    txt := PrettyModes(txt)
    txt := StrReplace(txt, "`n", "  ")
    if StrLen(txt) > 110
        txt := SubStr(txt, 1, 110) "…"
    mgrPrev.Text := " " head "`n " txt
}

; atajo de archivo desde el gestor: elige archivo(s) y arma la sintaxis solo
PickFile(*) {
    fs := FileSelect("M3", , "Elige el/los archivos que insertará el atajo (imagen, video, PDF…)")
    if !IsObject(fs) || !fs.Length
        return
    s := ""
    for f in fs
        s .= (s ? "|" : "") f
    mgrText.Value := "archivo:" s
    UpdateMgrPreview()
}

MgrNew(*) {
    global mgrSelLine, mgrSelRaw, mgrDirty
    mgrSelLine := 0, mgrSelRaw := ""
    mgrName.Value := "", mgrText.Value := ""
    mgrL1.Value := "", mgrL2.Value := ""
    mgrInst.Value := 0
    UpdateMgrPreview()
    mgrDirty := false
}

MgrDup(*) {
    global mgrSelLine, mgrSelRaw, mgrDirty
    mgrSelLine := 0, mgrSelRaw := ""
    if mgrName.Value != ""
        mgrName.Value := mgrName.Value "2"
    UpdateMgrPreview()
    mgrDirty := true   ; el duplicado aún no está guardado
}

MgrSave(*) {
    global mgrSelLine, mgrSelRaw, mgrNewSec, rawLines
    name := Trim(mgrName.Value)
    if name = "" || !RegExMatch(name, "^[^\s\[\]=!:|{}]+$") {
        MsgBox("El nombre no puede estar vacío ni llevar espacios, corchetes, `=`, `!`, `:` ni `|`.`n`nEjemplos válidos: con, gracias, precio2", "Midword", "Icon!")
        return
    }
    txt := StrReplace(mgrText.Value, "`r`n", "`n")
    if Trim(txt) = "" {
        MsgBox("Escribe el texto que se va a insertar.", "Midword", "Icon!")
        return
    }
    if SubStr(txt, 1, 8) = "archivo:" {
        falta := false
        for f in StrSplit(Trim(SubStr(txt, 9)), "|")
            if Trim(f) != "" && !FileExist(Trim(f))
                falta := true
        if falta && MsgBox("Alguna ruta de archivo no existe en este momento.`n`n¿Guardar de todos modos?", "Midword", "YesNo Icon?") = "No"
            return
    }
    l1 := ParseLevel(mgrL1.Value), l2 := ParseLevel(mgrL2.Value)
    if l2.Length && !l1.Length {
        MsgBox("Hay opciones en el nivel 2 pero el nivel 1 está vacío.`nLlena primero el nivel 1.", "Midword", "Icon!")
        return
    }
    ; tokens duplicados en un nivel (ej. '10 páginas' y '10 días' → '10')
    for lvl in [l1, l2] {
        seen := Map(), seen.CaseSense := "Off"
        for o in lvl {
            if seen.Has(o.tok) {
                MsgBox("Dos opciones de un mismo nivel generan el token '" o.tok "' y se pisarían entre sí.`nDiferéncialas escribiéndolas como  token: Etiqueta  (una por línea).", "Midword", "Icon!")
                return
            }
            seen[o.tok] := true
        }
    }
    ; un instantáneo que es prefijo de otro atajo se dispara antes de
    ; poder terminar de escribir el otro
    if mgrInst.Value {
        conf := ""
        for trig in shortcuts
            if trig != name && InStr(trig, name) = 1 {
                conf := trig
                break
            }
        if conf != "" && MsgBox("El atajo " PREFIX name " es instantáneo y además es el inicio de " PREFIX conf ": se insertará solo antes de que puedas escribir el otro.`n`n¿Guardar de todos modos?", "Midword", "YesNo Icon?") = "No"
            return
    }
    if l1.Length && !InStr(txt, "{1}") {
        if MsgBox("El texto no contiene {1}, así que la opción elegida del nivel 1 no aparecerá en él.`n`n¿Guardar de todos modos?", "Midword", "YesNo Icon?") = "No"
            return
    }
    if l2.Length && !InStr(txt, "{2}") {
        if MsgBox("El texto no contiene {2}, así que la opción elegida del nivel 2 no aparecerá en él.`n`n¿Guardar de todos modos?", "Midword", "YesNo Icon?") = "No"
            return
    }
    newLine := SerializeAtajo(name, mgrInst.Value, txt, l1, l2)
    idx := RelocateSelLine()
    ; ¿el nombre ya lo usa otra línea del archivo?
    for i, ln in rawLines {
        if i = idx
            continue
        t := Trim(ln)
        if t = "" || SubStr(t, 1, 1) = "#"
            continue
        p := InStr(t, "=")
        if !p
            continue
        left := Trim(RegExReplace(Trim(SubStr(t, 1, p - 1)), "\[[^\]]*\]"))
        if SubStr(left, -1) = "!"
            left := Trim(SubStr(left, 1, -1))
        if left = name {
            if MsgBox("Ya existe un atajo llamado " PREFIX name " (línea " i ") y solo uno de los dos funcionará.`n`n¿Guardar de todos modos?", "Midword", "YesNo Icon?") = "No"
                return
            break
        }
    }
    if idx
        rawLines[idx] := newLine
    else {
        pos := SectionInsertPos(mgrNewSec)   ; nuevo: al final de su sección
        if pos {
            rawLines.InsertAt(pos, newLine)
            idx := pos
        } else {
            rawLines.Push(newLine)
            idx := rawLines.Length
        }
    }
    mgrSelLine := idx
    mgrSelRaw := newLine
    global mgrDirty := false
    SaveRawAndReload()
    TrayTip("Atajo " PREFIX name " guardado", "Midword")
}

MgrDelete(*) {
    global mgrSelLine, rawLines
    ; selección múltiple de la lista (Ctrl/Shift+clic)
    sel := [], row := 0
    while row := mgrLV.GetNext(row) {
        e := mgrRows[row]
        if e.kind != "sec" && e.line >= 1 && e.line <= rawLines.Length
            sel.Push(rawLines[e.line])
    }
    if sel.Length > 1 {
        if MsgBox("¿Eliminar " sel.Length " atajos seleccionados?", "Midword", "YesNo Icon?") = "No"
            return
        ReloadRawFromDisk()
        for content in sel {
            for i, ln in rawLines {
                if ln = content {
                    rawLines.RemoveAt(i)
                    break
                }
            }
        }
        SaveRawAndReload()
        MgrNew()
        return
    }
    idx := RelocateSelLine()
    if !idx {
        MsgBox("Selecciona primero un atajo de la lista.", "Midword", "Icon!")
        return
    }
    if MsgBox("¿Eliminar el atajo " PREFIX Trim(mgrName.Value) " ?", "Midword", "YesNo Icon?") = "No"
        return
    rawLines.RemoveAt(idx)
    SaveRawAndReload()
    MgrNew()
}

; muestra cómo quedará el atajo del formulario, con variables resueltas
MgrTest(*) {
    txt := StrReplace(mgrText.Value, "`r`n", "`n")
    if Trim(txt) = "" {
        MsgBox("Escribe primero el texto del atajo.", "Midword", "Icon!")
        return
    }
    if SubStr(txt, 1, 8) = "archivo:" {
        MsgBox("Este atajo adjunta archivo(s): pruébalo escribiéndolo en cualquier aplicación.", "Midword", "Iconi")
        return
    }
    l1 := ParseLevel(mgrL1.Value), l2 := ParseLevel(mgrL2.Value)
    if l1.Length
        txt := StrReplace(txt, "{1}", l1[1].lab)
    if l2.Length
        txt := StrReplace(txt, "{2}", l2[1].lab)
    if !ResolveVars(&txt)
        return
    txt := StrReplace(txt, Chr(2), "{")
    txt := StrReplace(txt, "{cursor}", "‸")
    if SubStr(txt, 1, 8) = "teclear:"
        txt := SubStr(txt, 9)
    MsgBox("Así se insertará (‸ = posición del cursor):`n`n" txt, "Midword — Probar", "Iconi")
}

; línea donde insertar un atajo nuevo para que quede al final de la
; sección `sec` (justo antes del siguiente encabezado "# ── … ──").
; 0 = al final del archivo (sección vacía/última/no encontrada).
SectionInsertPos(sec) {
    if sec = ""
        return 0
    inSec := false
    for i, ln in rawLines {
        if RegExMatch(Trim(ln), "^#\s*──\s*(.+?)\s*──", &ms) {
            if inSec
                return i
            inSec := (ms[1] = sec)
        }
    }
    return 0
}

; mueve el atajo seleccionado una posición arriba/abajo (intercambia
; con la línea de atajo adyacente, saltando comentarios y vacías)
MgrMove(d, *) {
    global rawLines, mgrSelLine, mgrSelRaw
    idx := RelocateSelLine()
    if !idx {
        MsgBox("Selecciona primero un atajo de la lista.", "Midword", "Icon!")
        return
    }
    j := idx + d
    while j >= 1 && j <= rawLines.Length {
        t := Trim(rawLines[j])
        if t != "" && SubStr(t, 1, 1) != "#"
            break
        j += d
    }
    if j < 1 || j > rawLines.Length
        return
    tmp := rawLines[idx], rawLines[idx] := rawLines[j], rawLines[j] := tmp
    mgrSelLine := j
    SaveRawAndReload()
}

; lee atajos.txt tolerando la codificación: UTF-8 (con o sin BOM) y,
; si aparecen bytes inválidos (guardado como ANSI), reintenta en CP0
ReadConfigText() {
    raw := FileRead(CONFIG, "UTF-8")
    if InStr(raw, Chr(0xFFFD))
        try raw := FileRead(CONFIG, "CP0")
    return raw
}

; relee atajos.txt desde disco a rawLines (por si se editó por fuera)
ReloadRawFromDisk() {
    global rawLines
    if !FileExist(CONFIG)
        return
    cur := StrSplit(StrReplace(ReadConfigText(), "`r"), "`n")
    while cur.Length && Trim(cur[cur.Length]) = ""
        cur.Pop()
    rawLines := cur
}

; ubica la línea en edición tras releer el archivo: primero por número,
; y si el archivo cambió por fuera, por su contenido original.
; Devuelve 0 si es un atajo nuevo o la línea ya no existe.
RelocateSelLine() {
    ReloadRawFromDisk()
    if mgrSelRaw = ""
        return 0
    if mgrSelLine >= 1 && mgrSelLine <= rawLines.Length && rawLines[mgrSelLine] = mgrSelRaw
        return mgrSelLine
    for i, ln in rawLines
        if ln = mgrSelRaw
            return i
    return 0
}

SaveRawAndReload() {
    s := ""
    for ln in rawLines
        s .= ln "`r`n"
    BackupConfig()
    ; escritura atómica: primero a un temporal y luego rename;
    ; si algo falla a medias, atajos.txt queda intacto
    tmp := CONFIG ".tmp"
    if FileExist(tmp)
        FileDelete(tmp)
    FileAppend(s, tmp, "UTF-8")
    FileMove(tmp, CONFIG, 1)
    LoadShortcuts()
    RefreshMgrList()
}

; copia atajos.txt a respaldos\ antes de cada guardado; conserva los 10 últimos
BackupConfig() {
    if !FileExist(CONFIG)
        return
    try {
        bakDir := A_ScriptDir "\respaldos"
        DirCreate(bakDir)
        FileCopy(CONFIG, bakDir "\atajos-" A_Now ".txt", 1)
        baks := []
        loop files bakDir "\atajos-*.txt"
            baks.Push(A_LoopFileFullPath)
        ; el timestamp en el nombre hace que el orden alfabético sea cronológico
        while baks.Length > 10 {
            FileDelete(baks[1])
            baks.RemoveAt(1)
        }
    }
}

; --- importar un bloque generado por IA (o copiado de otra PC) ---

MgrImport(*) {
    global impGui, impEdit
    if !impGui {
        impGui := Gui("-MaximizeBox +Owner" mgrGui.Hwnd, "Importar atajos")
        impGui.BackColor := CLR_BG
        impGui.OnEvent("Close", (*) => (impGui.Hide(), 1))
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", impGui.Hwnd, "int", 20, "int*", 1, "int", 4)
        card := impGui.Add("Text", "x12 y10 w524 h290 Background" CLR_SURFACE)
        RoundCtrl(card, 524, 290, 24)
        impGui.SetFont("s9 w400 c" CLR_MUTED, "Segoe UI")
        impGui.Add("Text", "x28 y22 w492 Background" CLR_SURFACE,
            "Pega aquí las líneas generadas por la IA (con PROMPT_PARA_IA.txt) y presiona Importar.`nLas líneas válidas se agregan al final; las inválidas se omiten y se te avisa.")
        impGui.SetFont("s10 w400 c" CLR_TEXT, "Consolas")
        impEdit := impGui.Add("Edit", "x28 y58 w492 h226 Multi WantReturn VScroll Background" CLR_SURF_ALT)
        Pill(impGui, 416, 310, 120, 30, "Importar", CLR_ACCENT, "FFFFFF", DoImport)
    }
    impEdit.Value := ""
    impGui.Show("w548 h352")
}

DoImport(*) {
    global rawLines
    ok := 0, bad := [], dup := []
    toAdd := []
    nLn := 0
    seen := Map(), seen.CaseSense := "Off"   ; nombres ya existentes
    for e in order
        seen[e.kind = "group" ? e.name : e.trig] := true
    for ln in StrSplit(impEdit.Value, "`n", "`r") {
        nLn++
        t := Trim(ln)
        if t = ""
            continue
        if SubStr(t, 1, 1) = "#" {
            toAdd.Push(t)
            continue
        }
        pos := InStr(t, "=")
        left := pos ? Trim(SubStr(t, 1, pos - 1)) : ""
        if SubStr(left, -1) = "!"
            left := Trim(SubStr(left, 1, -1))
        nameOnly := RegExReplace(left, "\[[^\]]*\]", "")
        if !pos || nameOnly = "" || RegExMatch(nameOnly, "[\s\[\]:|{}]") {
            bad.Push(nLn)
            continue
        }
        if seen.Has(nameOnly) {   ; ya existe o vino repetido en el bloque
            dup.Push(nLn)
            continue
        }
        seen[nameOnly] := true
        toAdd.Push(t)
        ok++
    }
    if !ok {
        MsgBox("No se encontró ninguna línea nueva para importar" (dup.Length ? " (todas ya existían)." : "."), "Midword", "Icon!")
        return
    }
    ReloadRawFromDisk()   ; no pisar cambios externos hechos mientras tanto
    for t in toAdd
        rawLines.Push(t)
    SaveRawAndReload()
    msg := "Se importaron " ok " atajo(s)."
    if bad.Length
        msg .= "`nLíneas omitidas por formato inválido: " JoinNums(bad)
    if dup.Length
        msg .= "`nLíneas omitidas por nombre duplicado: " JoinNums(dup)
    impGui.Hide()
    MsgBox(msg, "Midword", "Iconi")
}
