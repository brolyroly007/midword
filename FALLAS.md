# Fallas detectadas en la revalidación — Midword

Origen: revisión línea por línea posterior a completar MEJORAS.md (2026-07-06).
Estado global: sintaxis ✅ · selftest 18/18 ✅ · smoke de arranque ✅ — pero hay fallas funcionales encontradas leyendo el código.

**GOAL del loop:** corregir TODAS las fallas de este archivo. Por cada una: implementar el fix, validar sintaxis, correr `--selftest`, marcar ✅ HECHO con nota y hacer commit. El loop termina cuando todas estén ✅ (o ⏭️ con motivo justificado) y la prueba de humo end-to-end (F8) pase.

---

## ✅ HECHO — 🔴 F1 — `ExpandTrig` revienta si el atajo desapareció del archivo
> Fix: guard `if !shortcuts.Has(trig) { ResetState(); return }` al inicio de `ExpandTrig`.
`txt := shortcuts[trig]` sin guard. Escenario: el menú está abierto, el timer de 3 s recarga un `atajos.txt` editado por fuera donde ese atajo ya no existe, y el usuario presiona Enter → excepción (va a `midword.log`, pero la expansión muere y lo escrito queda a medias). Fix: `if !shortcuts.Has(trig) { ResetState(); return }` al inicio.

## ✅ HECHO — 🔴 F2 — Cancelar un `{input:…}` pierde lo que habías escrito
> Fix: nuevo flag `expandCanceled` que `InsertText` activa cuando `ResolveVars` devuelve false; `ExpandTrig` lo detecta y reescribe lo borrado con `SendText(PREFIX curTyped)`, sin contar uso ni sonar ni dejar deshacer colgado.
`ExpandTrig` borra `//atajo` con backspaces ANTES de llamar a `InsertText`; si el usuario cancela el InputBox, `ResolveVars` devuelve false y no se inserta nada — pero lo tipeado ya se borró. Fix: si `InsertText` devolvió `""` por cancelación, reescribir lo borrado (`SendText(PREFIX curTyped)`); distinguir "canceló" de "no hay deshacer" (p. ej. `ResolveVars` con código de retorno propio o flag global).

## 🟠 F3 — "Duplicar" no marca el formulario como sucio
`MgrDup` cambia el nombre y deja contenido nuevo sin guardar, pero no pone `mgrDirty := true` → cambiar de selección, "+ Nuevo" o cerrar descartan el duplicado SIN el aviso de cambios sin guardar. Fix: `mgrDirty := true` al final de `MgrDup`.

## 🟠 F4 — Aviso de descarte repetido con multi-selección
Con cambios sin guardar y una selección Ctrl/Shift de N filas, `MgrItemSelect` dispara `MgrDirtyOk()` por CADA fila seleccionada → N MsgBox seguidos. Fix: si el usuario ya respondió "Sí, descartar" en esta ráfaga (o `mgrDirty` quedó en false tras el primer aviso), no volver a preguntar; con que el primer aviso limpie `mgrDirty` basta — verificar que efectivamente ocurre y que no se vuelve a marcar dirty durante la carga de cada fila (revisar orden de eventos Change durante `LoadEntryToForm`).

## 🟡 F5 — El buscador del gestor no ignora tildes
El menú busca con `Norm()` (sin tildes/mayúsculas) pero `RefreshMgrList` compara con `InStr` directo: buscar "numero" en el gestor no encuentra "número". Fix: aplicar `Norm()` a filtro, label y preview.

## 🟡 F6 — Los prefijos `teclear:` y `html:` se muestran crudos en las vistas previas
`EntryPreview` (menú), `UpdateMgrPreview` (gestor) y `ShowFullPreview` (tooltip) muestran "teclear:Hola..." / "html:<b>..." tal cual. Fix: en las previews, quitar el prefijo y añadir un marcador amable ("⌨ " para teclear, "🅷 " o "✱ " para html), como ya se hace con `archivo:` → 📎.

## 🟡 F7 — El TrayTip de advertencias de carga puede truncarse
`LoadShortcuts` concatena hasta 5 categorías de advertencias en un solo TrayTip (límite práctico ~256 chars). Con muchos problemas, se corta sin indicación. Fix: acortar el mensaje (máx. ~3 líneas + "…") y volcar el detalle completo a `midword.log`.

## 🔵 F8 — Prueba de humo end-to-end automatizada
`--selftest` cubre el parser pero nada de UI/expansión. Crear `qa_smoke.ahk` (no se compila, vive en `tests/`): lanza `midword.ahk` con un `atajos.txt` temporal, abre Notepad, tipea `//qatest` + Tab con `SendText`/`SendEvent`, lee el contenido del Edit de Notepad y verifica la expansión; limpia todo al salir (cierra Notepad sin guardar y termina el proceso midword de prueba). Salida por stdout + exit code, para poder engancharlo luego al CI si resulta estable.

---

## Registro
| Falla | Estado |
|---|---|
| F1 | ✅ |
| F2 | ✅ |
| F3 | pendiente |
| F4 | pendiente |
| F5 | pendiente |
| F6 | pendiente |
| F7 | pendiente |
| F8 | pendiente |
