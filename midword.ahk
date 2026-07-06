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

CONFIG := A_ScriptDir "\atajos.txt"
PREFIX := "//"

; --- Opciones (midword.ini es opcional; si no existe se usan los defaults) ---
;   [opciones]
;   min_caracteres=1   → no mostrar el menú hasta escribir N letras después de //
;   hotkey_pausa=^!m   → atajo para pausar/reanudar (sintaxis de hotkeys de AHK)
INI := A_ScriptDir "\midword.ini"
MIN_CHARS := 0
try MIN_CHARS := Integer(IniRead(INI, "opciones", "min_caracteres", "0"))

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

; --- Estado del menú ---
typedBuf := ""          ; últimas teclas escritas por el usuario
curTyped := ""          ; lo escrito después de //
eraseLen := 0           ; caracteres a borrar al insertar
suggesting := false
entries := []           ; entradas mostradas en el menú principal
sugGui := 0
rows := []
rowByHwnd := Map()
selIdx := 1
menuX := 0, menuY := 0, menuHH := 0, menuRH := 0, menuW := 0
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
A_TrayMenu.Add()
A_TrayMenu.Add("Salir", (*) => ExitApp())
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
        A_IconTip := "Midword (en pausa)"
        TrayTip("En pausa: no se mostrarán sugerencias", "Midword")
    } else {
        ih.Start()
        A_TrayMenu.Uncheck("Pausar (no sugerir)")
        A_IconTip := "Midword"
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

; hotkey opcional para pausar/reanudar, p. ej.  [opciones] hotkey_pausa=^!m
try {
    hkPausa := IniRead(INI, "opciones", "hotkey_pausa", "")
    if hkPausa != ""
        Hotkey(hkPausa, TogglePause)
}

; --- Recarga automática cuando se edita atajos.txt ---
SetTimer(CheckConfigChanged, 3000)

; --- Teclas activas solo mientras el menú está visible ---
#HotIf suggesting && CanGoRight()
Right::GoRight()
#HotIf suggesting && (subActive || sub2Active)
Left::GoLeft()
#HotIf suggesting
Tab::AcceptKey()
Enter::AcceptKey()
NumpadEnter::AcceptKey()
Esc::ResetState()
Down::NavKey(1)
Up::NavKey(-1)
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
    global rawLines := StrSplit(StrReplace(FileRead(CONFIG, "UTF-8"), "`r"), "`n")
    while rawLines.Length && Trim(rawLines[rawLines.Length]) = ""
        rawLines.Pop()
    badLines := []
    lineNo := 0
    for raw in rawLines {
        lineNo++
        line := Trim(raw)
        if line = "" || SubStr(line, 1, 1) = "#"
            continue
        pos := InStr(line, "=")
        if !pos {
            badLines.Push(lineNo)
            continue
        }
        trig := Trim(SubStr(line, 1, pos - 1))
        txt := StrReplace(SubStr(line, pos + 1), "\n", "`n")
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
                for o in StrSplit(mb[1], "|") {
                    o := Trim(o)
                    if o = ""
                        continue
                    c := InStr(o, ":")
                    d.Push({tok: c ? Trim(SubStr(o, 1, c - 1)) : o
                          , lab: c ? Trim(SubStr(o, c + 1)) : o})
                }
                if d.Length
                    dims.Push(d)
                p2 := mb.Pos + mb.Len
            }
            if !dims.Length
                continue
            base := mv[1]
            variants := []
            if dims.Length = 1 {
                for o in dims[1] {
                    vTrig := base o.tok
                    shortcuts[vTrig] := StrReplace(txt, "{1}", o.lab)
                    if isInstant
                        instant[vTrig] := true
                    variants.Push(vTrig)
                }
            } else {
                for o1 in dims[1] {
                    for o2 in dims[2] {
                        vTrig := base o1.tok o2.tok
                        shortcuts[vTrig] := StrReplace(StrReplace(txt, "{1}", o1.lab), "{2}", o2.lab)
                        if isInstant
                            instant[vTrig] := true
                        variants.Push(vTrig)
                    }
                }
            }
            order.Push({kind: "group", name: base, dims: dims, variants: variants, template: txt, line: lineNo})
        } else {
            shortcuts[trig] := txt
            if isInstant
                instant[trig] := true
            order.Push({kind: "item", trig: trig, line: lineNo})
        }
    }
    if badLines.Length {
        s := ""
        for bn in badLines
            s .= (s ? ", " : "") bn
        TrayTip("Línea(s) ignoradas en atajos.txt (les falta el '='): " s, "Midword — revisa el archivo", "Icon!")
    }
}

; ==================== Detección de escritura ====================

HandleChar(hook, char) {
    global typedBuf
    typedBuf .= char
    if StrLen(typedBuf) > 80
        typedBuf := SubStr(typedBuf, -80)
    UpdateSuggestions()
}

HandleKeyDown(hook, vk, sc) {
    global typedBuf
    if vk = 0x08 {  ; Backspace
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

UpdateSuggestions() {
    global entries, curTyped, eraseLen
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
    ; primero coincidencias de prefijo (los grupos aparecen como UNA
    ; fila); luego coincidencias dentro del nombre o del texto
    m := [], m2 := []
    for entry in order {
        if entry.kind = "group" {
            if typed = "" || InStr(entry.name, typed) = 1
                m.Push(entry)                          ; fila única desglosable
            else if InStr(typed, entry.name) = 1 {
                for vTrig in entry.variants            ; //con1 filtra con10, con15…
                    if InStr(vTrig, typed) = 1
                        m.Push({kind: "item", trig: vTrig})
            } else if InStr(entry.name, typed) || InStr(entry.template, typed)
                m2.Push(entry)
        } else {
            txt := shortcuts[entry.trig]
            if typed = "" || InStr(entry.trig, typed) = 1
                m.Push(entry)
            else if InStr(entry.trig, typed) || InStr(txt, typed)
                m2.Push(entry)
        }
    }
    for entry in m2
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

DimRange(d) {
    return d.Length > 1 ? d[1].lab "–" d[d.Length].lab : d[1].lab
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
        SplitPath(Trim(SubStr(txt, 9)), &fname)
        return "📎 " fname
    }
    txt := StrReplace(txt, "`n", "  ")
    if StrLen(txt) > 56
        txt := SubStr(txt, 1, 56) "…"
    return txt
}

BuildMenu() {
    global sugGui, suggesting, rows, rowByHwnd, selIdx
    global menuX, menuY, menuHH, menuRH, menuW
    CloseSub()
    if sugGui
        sugGui.Destroy()
    rows := [], rowByHwnd := Map()
    selIdx := 1

    W := 620, HH := 30, RH := 36
    n := Min(entries.Length, 10)
    extra := entries.Length - n
    FH := extra > 0 ? 24 : 0
    H := 1 + HH + n * RH + FH + 1

    maxLen := 0
    loop n {
        L := StrLen(EntryLabel(entries[A_Index]))
        if L > maxLen
            maxLen := L
    }
    TW := 26 + maxLen * 9
    if TW > 200
        TW := 200

    sugGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")
    sugGui.BackColor := CLR_BORDER
    sugGui.MarginX := 0, sugGui.MarginY := 0

    ; --- header crema: título + botón "ver todos" + hints ---
    sugGui.SetFont("s9 c" CLR_ACCENT " w700", "Segoe UI")
    sugGui.Add("Text", "x1 y1 w110 h" HH " Background" CLR_BG " +0x200", "   ●  Midword")
    btn := sugGui.Add("Text", "x111 y1 w90 h" HH " Background" CLR_BG " +0x200", "  ☰ ver todos")
    btn.OnEvent("Click", ShowAllClick)
    sugGui.SetFont("s8 c" CLR_MUTED " w400", "Segoe UI")
    sugGui.Add("Text", "x201 y1 w" (W - 2 - 200) " h" HH " Background" CLR_BG " +0x200 Right",
        "↑↓ elegir  ·  ▸ desglosar  ·  Tab/Enter insertar  ·  Esc   ")

    ; --- filas ---
    loop n {
        i := A_Index
        entry := entries[i]
        y := 1 + HH + (i - 1) * RH
        sel := (i = selIdx)
        rowBg := sel ? CLR_ACC_LITE : CLR_SURFACE

        bar := sugGui.Add("Text", "x1 y" y " w4 h" RH " Background" (sel ? CLR_ACCENT : rowBg))
        sugGui.SetFont("s10 c" CLR_ACC_DARK " w700", "Consolas")
        t := sugGui.Add("Text", "x5 y" y " w" TW " h" RH " Background" rowBg " +0x200", "  " EntryLabel(entry))
        sugGui.SetFont("s10 c" CLR_BODY " w400", "Segoe UI")
        pv := sugGui.Add("Text", "x" (5 + TW) " y" y " w" (W - 1 - 5 - TW) " h" RH " Background" rowBg " +0x200", EntryPreview(entry))

        for ctrl in [bar, t, pv] {
            ctrl.OnEvent("Click", AcceptIndex.Bind(i))
            rowByHwnd[ctrl.Hwnd] := i
        }
        rows.Push({bar: bar, trig: t, prev: pv})
    }

    if extra > 0 {
        sugGui.SetFont("s8 c" CLR_MUTED " w400", "Segoe UI")
        sugGui.Add("Text", "x1 y" (1 + HH + n * RH) " w" (W - 2) " h" FH " Background" CLR_SURF_ALT " +0x200",
            "      sigue escribiendo… (+" extra " atajos más)")
    }

    ; --- posición junto al cursor de texto ---
    x := 0, y := 0
    CoordMode "Caret", "Screen"
    if !CaretGetPos(&x, &y) {
        CoordMode "Mouse", "Screen"
        MouseGetPos(&x, &y)
    }
    y += 24
    if x > A_ScreenWidth - (W + 380)
        x := A_ScreenWidth - (W + 380)   ; deja sitio a los submenús
    if x < 0
        x := 0
    if y > A_ScreenHeight - (H + 60)
        y -= H + 50
    menuX := x, menuY := y, menuHH := HH, menuRH := RH, menuW := W
    sugGui.Show("x" x " y" y " w" W " h" H " NoActivate")
    WinSetRegion("0-0 w" W " h" H " R14-14", sugGui)
    suggesting := true
    SetTimer(HoverWatch, 80)
    ; si la primera fila es un grupo, mostrar su desglose de una vez
    if entries[1].kind = "group"
        OpenSub(1)
}

; ==================== Submenú nivel 1 ====================

OpenSub(i) {
    global subGui, subEntry, subRows, subByHwnd, subSel, subActive, subForIdx
    global subX, subY, subW
    if subForIdx = i && subGui
        return
    CloseSub()
    entry := entries[i]
    if entry.kind != "group"
        return
    subEntry := entry
    subSel := 0, subActive := false, subForIdx := i

    d1 := entry.dims[1]
    hasL2 := entry.dims.Length > 1
    n := d1.Length, RH := menuRH

    maxLab := 0
    for o in d1
        if StrLen(o.lab) > maxLab
            maxLab := StrLen(o.lab)
    LW := 30 + maxLab * 9
    W2 := LW + (hasL2 ? 40 : 130)
    if W2 < 150
        W2 := 150
    H2 := 1 + n * RH + 1

    subGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")
    subGui.BackColor := CLR_BORDER
    subGui.MarginX := 0, subGui.MarginY := 0

    loop n {
        j := A_Index
        y := 1 + (j - 1) * RH
        subGui.SetFont("s10 c" CLR_ACC_DARK " w700", "Consolas")
        o := subGui.Add("Text", "x1 y" y " w" LW " h" RH " Background" CLR_SURFACE " +0x200", "   " d1[j].lab)
        if hasL2 {
            subGui.SetFont("s10 c" CLR_MUTED " w400", "Segoe UI")
            tr := subGui.Add("Text", "x" (1 + LW) " y" y " w" (W2 - 2 - LW) " h" RH " Background" CLR_SURFACE " +0x200", "▸")
        } else {
            subGui.SetFont("s9 c" CLR_MUTED " w400", "Consolas")
            tr := subGui.Add("Text", "x" (1 + LW) " y" y " w" (W2 - 2 - LW) " h" RH " Background" CLR_SURFACE " +0x200", PREFIX entry.variants[j])
        }
        for ctrl in [o, tr] {
            ctrl.OnEvent("Click", AcceptSub.Bind(j))
            subByHwnd[ctrl.Hwnd] := j
        }
        subRows.Push({opt: o, trig: tr})
    }

    x := menuX + menuW - 6
    y := menuY + menuHH + (i - 1) * RH
    if x + W2 > A_ScreenWidth
        x := menuX - W2 + 6
    if y + H2 > A_ScreenHeight - 50
        y := A_ScreenHeight - 50 - H2
    subX := x, subY := y, subW := W2
    subGui.Show("x" x " y" y " w" W2 " h" H2 " NoActivate")
    WinSetRegion("0-0 w" W2 " h" H2 " R12-12", subGui)
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
    bg := sel ? CLR_ACC_LITE : CLR_SURFACE
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
        if StrLen(o.lab) > maxLab
            maxLab := StrLen(o.lab)
    W3 := 60 + maxLab * 9
    if W3 < 130
        W3 := 130
    H3 := 1 + n * RH + 1

    sub2Gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")
    sub2Gui.BackColor := CLR_BORDER
    sub2Gui.MarginX := 0, sub2Gui.MarginY := 0

    loop n {
        k := A_Index
        y := 1 + (k - 1) * RH
        sub2Gui.SetFont("s10 c" CLR_ACC_DARK " w700", "Consolas")
        o := sub2Gui.Add("Text", "x1 y" y " w" (W3 - 2) " h" RH " Background" CLR_SURFACE " +0x200", "   " d2[k].lab)
        o.OnEvent("Click", AcceptSub2.Bind(k))
        sub2ByHwnd[o.Hwnd] := k
        sub2Rows.Push(o)
    }

    x := subX + subW - 6
    y := subY + (j - 1) * RH
    if x + W3 > A_ScreenWidth
        x := subX - W3 + 6
    if y + H3 > A_ScreenHeight - 50
        y := A_ScreenHeight - 50 - H3
    sub2Gui.Show("x" x " y" y " w" W3 " h" H3 " NoActivate")
    WinSetRegion("0-0 w" W3 " h" H3 " R12-12", sub2Gui)
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
        sub2Rows[sub2Sel].Opt("Background" CLR_SURFACE)
        sub2Rows[sub2Sel].Redraw()
    }
    sub2Sel := k
    if k >= 1 && k <= sub2Rows.Length {
        sub2Rows[k].Opt("Background" CLR_ACC_LITE)
        sub2Rows[k].Redraw()
    }
}

; ==================== Selección y navegación ====================

StyleRow(i, sel) {
    r := rows[i]
    bg := sel ? CLR_ACC_LITE : CLR_SURFACE
    r.bar.Opt("Background" (sel ? CLR_ACCENT : bg))
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
    if entries[i].kind = "group"
        OpenSub(i)
    else
        CloseSub()
}

SelIsGroup() {
    return entries.Length && selIdx >= 1 && selIdx <= entries.Length
        && entries[selIdx].kind = "group"
}

SubHasL2() {
    return subEntry && subEntry.dims.Length > 1
}

CanGoRight() {
    return (!subActive && SelIsGroup()) || (subActive && !sub2Active && SubHasL2())
}

GoRight() {
    global subActive, sub2Active
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
    if i < 1
        i := rows.Length
    else if i > rows.Length
        i := 1
    SetSel(i)
}

; sigue el mouse: pasar sobre una fila la selecciona y desglosa grupos
HoverWatch() {
    global subActive, sub2Active
    if !suggesting {
        SetTimer(HoverWatch, 0)
        return
    }
    MouseGetPos , , &mwin, &mctrl, 2
    if sugGui && mwin = sugGui.Hwnd && rowByHwnd.Has(mctrl) {
        SetSel(rowByHwnd[mctrl])
        if subActive || sub2Active {
            subActive := false, sub2Active := false
            SetSubSel(0)
        }
    } else if subGui && mwin = subGui.Hwnd && subByHwnd.Has(mctrl) {
        j := subByHwnd[mctrl]
        subActive := true
        if j != subSel {
            SetSubSel(j)
            if SubHasL2()
                OpenSub2(j)
            else
                CloseSub2()
        }
    } else if sub2Gui && mwin = sub2Gui.Hwnd && sub2ByHwnd.Has(mctrl) {
        sub2Active := true
        SetSub2Sel(sub2ByHwnd[mctrl])
    }
}

; ==================== Aceptar e insertar ====================

AcceptIndex(idx, *) {
    if idx > entries.Length
        return
    if entries[idx].kind = "group" {
        SetSel(idx)
        GoRight()
    } else
        ExpandTrig(entries[idx].trig)
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
    ExpandTrig(entries[selIdx].trig)
}

; Borra lo escrito (//xxx) y lo reemplaza por el texto del atajo
ExpandTrig(trig) {
    global typedBuf, curTyped
    txt := shortcuts[trig]
    HideSuggestions()
    if eraseLen > 0
        SendInput("{BS " eraseLen "}")
    Sleep 50
    InsertText(txt)
    typedBuf := ""
    curTyped := ""
}

; Pone un archivo en el portapapeles como CF_HDROP (igual que Ctrl+C
; sobre el archivo en el Explorador): WhatsApp/Telegram lo adjuntan,
; Word/Docs insertan la imagen, Gmail lo adjunta.
SetClipboardFiles(path) {
    chars := StrLen(path) + 2              ; ruta + NUL + NUL final
    bytes := 20 + chars * 2                ; DROPFILES (20) + lista UTF-16
    hMem := DllCall("GlobalAlloc", "uint", 0x42, "uptr", bytes, "ptr")
    p := DllCall("GlobalLock", "ptr", hMem, "ptr")
    NumPut("uint", 20, p, 0)               ; pFiles = sizeof(DROPFILES)
    NumPut("int", 1, p, 16)                ; fWide = TRUE (UTF-16)
    StrPut(path, p + 20, "UTF-16")
    DllCall("GlobalUnlock", "ptr", hMem)
    if !DllCall("OpenClipboard", "ptr", A_ScriptHwnd)
        return false
    DllCall("EmptyClipboard")
    ok := DllCall("SetClipboardData", "uint", 15, "ptr", hMem, "ptr")  ; CF_HDROP
    DllCall("CloseClipboard")
    return !!ok
}

; Inserta un atajo de archivo (imagen, video, PDF…)
InsertFile(path) {
    if !FileExist(path) {
        TrayTip("No se encontró el archivo:`n" path, "Midword", "Icon!")
        return
    }
    saved := ClipboardAll()
    if !SetClipboardFiles(path) {
        A_Clipboard := saved
        return
    }
    Send("^v")
    Sleep 1200   ; adjuntar un archivo tarda más que pegar texto
    A_Clipboard := saved
}

; Inserta pegando desde el portapapeles: instantáneo, soporta
; textos largos y los saltos de línea NO envían el mensaje en
; WhatsApp/Telegram. Restaura lo que tenías copiado.
InsertText(txt) {
    ; atajos de archivo:  miatajo=archivo:C:\ruta\imagen.png
    if SubStr(txt, 1, 8) = "archivo:" {
        InsertFile(Trim(SubStr(txt, 9)))
        return
    }
    txt := StrReplace(txt, "{fecha_larga}", FormatTime(, "d 'de' MMMM 'de' yyyy"))
    txt := StrReplace(txt, "{fecha}", FormatTime(, "dd/MM/yyyy"))
    txt := StrReplace(txt, "{hora}", FormatTime(, "HH:mm"))
    txt := StrReplace(txt, "{dia}", FormatTime(, "dddd"))
    back := 0
    cp := InStr(txt, "{cursor}")
    if cp {
        back := StrLen(txt) - cp - StrLen("{cursor}") + 1
        txt := StrReplace(txt, "{cursor}", "")
    }
    saved := ClipboardAll()
    A_Clipboard := txt
    if ClipWait(1) {
        Send("^v")
        Sleep 250   ; dar tiempo a que la app procese el pegado
    }
    A_Clipboard := saved
    if back > 0
        Send("{Left " back "}")
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
    global suggesting, sugGui, rows, rowByHwnd, entries
    SetTimer(HoverWatch, 0)
    CloseSub()
    suggesting := false
    rows := [], rowByHwnd := Map(), entries := []
    if sugGui {
        sugGui.Destroy()
        sugGui := 0
    }
}

ResetState() {
    global typedBuf, curTyped
    typedBuf := ""
    curTyped := ""
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
    global mgrL1, mgrL2, mgrPrev, mgrCount
    if mgrGui {
        RefreshMgrList()
        mgrGui.Show()
        return
    }
    mgrGui := Gui("-MaximizeBox", "Midword")
    mgrGui.BackColor := CLR_BG
    mgrGui.OnEvent("Close", (*) => (mgrGui.Hide(), 1))
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
    cardL := mgrGui.Add("Text", "x12 y106 w330 h354 Background" CLR_SURFACE)
    RoundCtrl(cardL, 330, 354, 24)
    mgrGui.SetFont("s9 w400 c" CLR_MUTED, "Segoe UI")
    mgrGui.Add("Text", "x30 y120 w200 Background" CLR_SURFACE, "Buscar atajo:")
    mgrGui.SetFont("s10 w400 c" CLR_TEXT, "Segoe UI")
    mgrSearch := mgrGui.Add("Edit", "x30 y138 w294 Background" CLR_SURF_ALT)
    mgrSearch.OnEvent("Change", (*) => RefreshMgrList())
    mgrLV := mgrGui.Add("ListView", "x30 y172 w294 h270 -Multi -E0x200 Background" CLR_SURFACE, ["Atajo", "Texto"])
    mgrLV.OnEvent("ItemSelect", MgrItemSelect)
    mgrLV.ModifyCol(1, 92), mgrLV.ModifyCol(2, 178)

    ; ===== tarjeta derecha: formulario =====
    cardR := mgrGui.Add("Text", "x354 y106 w434 h354 Background" CLR_SURFACE)
    RoundCtrl(cardR, 434, 354, 24)
    X2 := 372
    mgrGui.SetFont("s9 w400 c" CLR_MUTED, "Segoe UI")
    mgrGui.Add("Text", "x" X2 " y118 w220 Background" CLR_SURFACE, "Nombre (lo escribirás como //nombre):")
    mgrGui.SetFont("s10 w400 c" CLR_TEXT, "Segoe UI")
    mgrName := mgrGui.Add("Edit", "x" X2 " y136 w180 Background" CLR_SURF_ALT)
    mgrName.OnEvent("Change", (*) => UpdateMgrPreview())
    mgrGui.SetFont("s9 w400 c" CLR_BODY, "Segoe UI")
    mgrInst := mgrGui.Add("Checkbox", "x" (X2 + 196) " y139 w200 Background" CLR_SURFACE, "Instantáneo (sin Tab)")

    mgrGui.SetFont("s9 w400 c" CLR_MUTED, "Segoe UI")
    mgrGui.Add("Text", "x" X2 " y168 w300 Background" CLR_SURFACE, "Texto a insertar (Enter = salto de línea):")
    Pill(mgrGui, X2 + 300, 160, 104, 26, "📎 archivo…", CLR_ACC_LITE, CLR_ACC_DARK, PickFile, "s9 w600")
    mgrGui.SetFont("s10 w400 c" CLR_TEXT, "Segoe UI")
    mgrText := mgrGui.Add("Edit", "x" X2 " y186 w398 h78 Multi WantReturn VScroll Background" CLR_SURF_ALT)
    mgrText.OnEvent("Change", (*) => UpdateMgrPreview())

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
    mgrL1.OnEvent("Change", (*) => UpdateMgrPreview())
    mgrL2 := mgrGui.Add("Edit", "x" (X2 + 206) " y332 w192 h58 Multi WantReturn VScroll Background" CLR_SURF_ALT)
    mgrL2.OnEvent("Change", (*) => UpdateMgrPreview())

    mgrGui.SetFont("s8 w700 c" CLR_ACCENT, "Segoe UI")
    mgrGui.Add("Text", "x" X2 " y398 w200 Background" CLR_SURFACE, "VISTA PREVIA")
    mgrGui.SetFont("s9 w400 c" CLR_BODY, "Segoe UI")
    mgrPrev := mgrGui.Add("Text", "x" X2 " y414 w398 h38 Background" CLR_ACC_LITE, "")
    RoundCtrl(mgrPrev, 398, 38, 12)

    ; ===== botonera pill =====
    Pill(mgrGui, 12, 472, 104, 30, "+ Nuevo", CLR_ACC_LITE, CLR_ACC_DARK, MgrNew)
    Pill(mgrGui, 124, 472, 104, 30, "Duplicar", CLR_ACC_LITE, CLR_ACC_DARK, MgrDup)
    Pill(mgrGui, 236, 472, 104, 30, "Eliminar", CLR_RED_LITE, CLR_RED, MgrDelete)
    Pill(mgrGui, 354, 472, 160, 30, "Importar desde IA", CLR_ACC_LITE, CLR_ACC_DARK, MgrImport)
    Pill(mgrGui, 522, 472, 130, 30, "Abrir archivo", CLR_ACC_LITE, CLR_ACC_DARK, EditConfig)
    Pill(mgrGui, 668, 472, 120, 30, "Guardar", CLR_ACCENT, "FFFFFF", MgrSave)

    RefreshMgrList()
    MgrNew()
    mgrGui.Show("w800 h516")
}

InsertVar(v, *) {
    DllCall("user32\SendMessageW", "ptr", mgrText.Hwnd, "uint", 0xC2, "ptr", 1, "wstr", v)
    UpdateMgrPreview()
}

RefreshMgrList() {
    global mgrRows
    if !mgrGui
        return
    if mgrCount
        mgrCount.Text := shortcuts.Count " frases  ·  " order.Length " atajos"
    filter := mgrSearch.Value
    mgrLV.Delete()
    mgrRows := []
    for entry in order {
        label := EntryLabel(entry)
        prev := EntryPreview(entry)
        if filter = "" || InStr(label, filter) || InStr(prev, filter) {
            mgrLV.Add(, label, prev)
            mgrRows.Push(entry)
        }
    }
}

MgrItemSelect(lv, item, selected) {
    if selected && item >= 1 && item <= mgrRows.Length
        LoadEntryToForm(mgrRows[item])
}

LoadEntryToForm(entry) {
    global mgrSelLine, mgrSelRaw
    mgrSelLine := entry.line
    mgrSelRaw := (entry.line >= 1 && entry.line <= rawLines.Length) ? rawLines[entry.line] : ""
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
        SplitPath(Trim(SubStr(txt, 9)), &pfn)
        txt := "📎 " pfn " (se adjunta el archivo)"
    }
    txt := StrReplace(txt, "`n", "  ")
    if StrLen(txt) > 110
        txt := SubStr(txt, 1, 110) "…"
    mgrPrev.Text := " " head "`n " txt
}

; atajo de archivo desde el gestor: elige el archivo y arma la sintaxis solo
PickFile(*) {
    f := FileSelect(3, , "Elige el archivo que insertará el atajo (imagen, video, PDF…)")
    if f = ""
        return
    mgrText.Value := "archivo:" f
    UpdateMgrPreview()
}

MgrNew(*) {
    global mgrSelLine, mgrSelRaw
    mgrSelLine := 0, mgrSelRaw := ""
    mgrName.Value := "", mgrText.Value := ""
    mgrL1.Value := "", mgrL2.Value := ""
    mgrInst.Value := 0
    UpdateMgrPreview()
}

MgrDup(*) {
    global mgrSelLine, mgrSelRaw
    mgrSelLine := 0, mgrSelRaw := ""
    if mgrName.Value != ""
        mgrName.Value := mgrName.Value "2"
    UpdateMgrPreview()
}

MgrSave(*) {
    global mgrSelLine, mgrSelRaw, rawLines
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
    if SubStr(txt, 1, 8) = "archivo:" && !FileExist(Trim(SubStr(txt, 9))) {
        if MsgBox("La ruta del archivo no existe en este momento.`n`n¿Guardar de todos modos?", "Midword", "YesNo Icon?") = "No"
            return
    }
    l1 := ParseLevel(mgrL1.Value), l2 := ParseLevel(mgrL2.Value)
    if l2.Length && !l1.Length {
        MsgBox("Hay opciones en el nivel 2 pero el nivel 1 está vacío.`nLlena primero el nivel 1.", "Midword", "Icon!")
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
    if idx
        rawLines[idx] := newLine
    else {
        rawLines.Push(newLine)
        idx := rawLines.Length
    }
    mgrSelLine := idx
    mgrSelRaw := newLine
    SaveRawAndReload()
    TrayTip("Atajo " PREFIX name " guardado", "Midword")
}

MgrDelete(*) {
    global mgrSelLine, rawLines
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

; relee atajos.txt desde disco a rawLines (por si se editó por fuera)
ReloadRawFromDisk() {
    global rawLines
    if !FileExist(CONFIG)
        return
    cur := StrSplit(StrReplace(FileRead(CONFIG, "UTF-8"), "`r"), "`n")
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
    ok := 0, bad := []
    toAdd := []
    nLn := 0
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
        toAdd.Push(t)
        ok++
    }
    if !ok {
        MsgBox("No se encontró ninguna línea válida para importar.", "Midword", "Icon!")
        return
    }
    ReloadRawFromDisk()   ; no pisar cambios externos hechos mientras tanto
    for t in toAdd
        rawLines.Push(t)
    SaveRawAndReload()
    msg := "Se importaron " ok " atajo(s)."
    if bad.Length {
        s := ""
        for bn in bad
            s .= (s ? ", " : "") bn
        msg .= "`nLíneas omitidas por formato inválido: " s
    }
    impGui.Hide()
    MsgBox(msg, "Midword", "Iconi")
}
