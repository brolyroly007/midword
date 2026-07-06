# Mejoras posibles (e imposibles) — Midword

Revisión exhaustiva del repo (`midword.ahk` v1.2.0, scripts, docs, branding, releases).
Fecha de revisión: 2026-07-06.

Leyenda de prioridad: 🔴 bug real / riesgo de datos · 🟠 importante · 🟡 deseable · 🔵 idea/opcional · 🚀 ambiciosa ("imposible" hoy).

---

## 1. Bugs confirmados en el código

### ✅ HECHO — 🔴 1.1 El `!` (instantáneo) se pierde en grupos de 2 niveles
> Corregido: la rama de 2 dimensiones en `LoadShortcuts()` ahora marca `instant[vTrig]` igual que la de 1 dimensión.
En `LoadShortcuts()`, la rama de 1 dimensión marca `instant[vTrig] := true`, pero la rama de 2 dimensiones (`dims.Length > 1`, línea ~236) **nunca lo hace**. Una línea como `mon[a|b][5|10]!=...` carga las variantes pero ninguna es instantánea. Además `LoadEntryToForm` lee `instant.Has(entry.variants[1])`, así que el gestor muestra el checkbox apagado y al guardar se pierde el `!` silenciosamente.

### ✅ HECHO — 🔴 1.2 Guardado no atómico: riesgo de perder `atajos.txt`
> Corregido: `SaveRawAndReload()` escribe a `atajos.txt.tmp` y hace `FileMove` (rename atómico); nueva función `BackupConfig()` copia el archivo a `respaldos\atajos-<timestamp>.txt` antes de cada guardado y conserva los 10 más recientes.
`SaveRawAndReload()` hace `FileDelete(CONFIG)` y luego `FileAppend(...)`. Si el proceso muere, el disco falla o el antivirus bloquea el append entre ambas llamadas, el usuario pierde TODOS sus atajos. Corregir con patrón temp + rename:
```autohotkey
FileAppend(s, CONFIG ".tmp", "UTF-8")
FileMove(CONFIG ".tmp", CONFIG, 1)
```
Y de paso guardar un respaldo rotativo en `respaldos\` (la carpeta ya está en `.gitignore`, la intención existía).

### ✅ HECHO — 🔴 1.3 Edición externa + gestor abierto = duplicados o sobrescritura
> Corregido: nueva `mgrSelRaw` guarda el contenido original de la línea en edición; al Guardar/Eliminar se relee el archivo desde disco (`ReloadRawFromDisk`) y la línea se reubica por número o por contenido (`RelocateSelLine`) — ni duplicados ni pisado de cambios externos. `DoImport` también relee antes de agregar.
- Si el archivo cambia por fuera mientras el gestor tiene un atajo cargado en el formulario, `CheckConfigChanged()` pone `mgrSelLine := 0`; al presionar **Guardar** el atajo se **agrega al final como duplicado** en vez de editar el original.
- Peor: `MgrSave` escribe `rawLines` (copia en memoria). Si el usuario editó el archivo a mano entre que abrió el gestor y guardó, esos cambios externos se pisan (lost update). Mitigación: releer el archivo justo antes de guardar y aplicar solo la línea cambiada, o avisar "el archivo cambió por fuera".

### ✅ HECHO — 🔴 1.4 El menú se abre al escribir cualquier URL
> Corregido: el `//` solo activa el menú si está al inicio o tras un separador (se ignora si lo precede letra, dígito, `:`, `.`, `/`, `\` o `-` → URLs y rutas ya no lo abren). Además se agregó `midword.ini` opcional con `[opciones] min_caracteres=N` para no abrir el menú hasta escribir N letras tras `//` (default 0; la expansión instantánea no se ve afectada).
Escribir `https://` deja `typedBuf` terminando en `//` con `typed = ""` → aparece el menú completo. Lo mismo al comentar código (`// TODO`). Es la molestia nº 1 en uso real fuera de WhatsApp. Opciones (combinables):
- Exigir que el `//` esté al inicio del buffer o precedido de espacio/salto (no de `:` ni letra).
- Opción de configuración: no mostrar el menú hasta que haya ≥1 carácter después de `//`.
- Lista negra de aplicaciones (ver 3.6).

### ✅ HECHO — 🟠 1.5 Fuga de memoria en `SetClipboardFiles`
> Corregido: `GlobalFree` si `OpenClipboard` o `SetClipboardData` fallan, y reintento ×5 (30 ms) cuando otro proceso tiene el portapapeles abierto.
Si `OpenClipboard` o `SetClipboardData` fallan, el `hMem` de `GlobalAlloc` nunca se libera (`GlobalFree`). Fuga pequeña pero real; además no hay reintento si otro proceso tiene el portapapeles abierto (caso común con gestores de portapapeles).

### ✅ HECHO — 🟠 1.6 Desincronización del buffer de tecleo
> Mitigado: Ctrl+Backspace resetea el buffer (no se puede saber cuánto borró), y cualquier carácter de control recibido por el hook (Ctrl+A, Ctrl+V…) también resetea, porque el contenido del campo pudo cambiar. La edición con mouse dentro del mismo campo ya reseteaba vía clic.
`typedBuf` solo modela tecla-a-tecla:
- **Ctrl+Backspace** (borrar palabra) resta 1 solo carácter del buffer.
- Seleccionar texto y escribir encima, o mover el cursor con clic dentro del mismo campo, desincroniza `eraseLen` → al expandir se borran caracteres de más o de menos.
Mitigación: resetear el buffer también con Ctrl+Backspace, Ctrl+A, y considerar el clic izquierdo dentro de un campo de texto (hoy solo resetea si el clic no fue sobre el menú, lo cual está bien, pero Ctrl+Backspace no está cubierto).

### ✅ HECHO — 🟠 1.7 Restauración del portapapeles con `Sleep` fijo
> Resuelto con `delay_pegar` y `delay_archivo` configurables en `midword.ini` (defaults 250/1200 ms). Refinamiento posible a futuro: detectar el dueño del portapapeles en vez de esperar.
`InsertText` espera 250 ms y `InsertFile` 1200 ms antes de restaurar el portapapeles. En apps lentas (Electron pesado, RDP, WhatsApp Web con lag) el Ctrl+V se procesa DESPUÉS de restaurar → se pega el contenido viejo del portapapeles. Mejoras: delay configurable en `atajos.txt`/ini, o restaurar con un timer más largo no bloqueante, o detectar el `WM_RENDERFORMAT`/dueño del portapapeles.

### ✅ HECHO — 🟠 1.8 Grupos con 3+ niveles se aceptan y fallan en silencio
> Ahora los niveles extra se recortan y el TrayTip de carga avisa la línea; el aviso combina también líneas sin `=` y tokens repetidos (helper `JoinNums`).
El regex de `LoadShortcuts` acepta `nombre[a|b][1|2][x|y]=` pero el código solo usa `dims[1]` y `dims[2]`: el tercer nivel se ignora y `{3}` queda literal en el texto. Avisar en el TrayTip de líneas inválidas (hoy solo avisa por falta de `=`).

### ✅ HECHO — 🟠 1.9 Colisión de tokens en `AutoTok`
> Doble protección: al cargar, las opciones con token repetido en un nivel se omiten y se avisa la línea; en el gestor, Guardar valida los niveles y explica cómo diferenciarlas con `token: Etiqueta`.
`"10 páginas"` y `"10 días"` generan el mismo token `10`; en un grupo, dos opciones con el mismo token producen variantes con el mismo trigger y una pisa a la otra sin aviso. Validar duplicados de token al guardar/parsear.

### 🟡 1.10 Triggers duplicados no se detectan
Dos líneas `con=...` conviven: el `Map` se queda con la última pero `order` muestra ambas en el menú (la primera inserta el texto de la segunda). Ni `MgrSave` ni `DoImport` avisan de duplicados contra los existentes.

### 🟡 1.11 `{cursor}` y `{Left n}` cuentan unidades UTF-16
`back := StrLen(txt) - cp - ...` cuenta code units: si después de `{cursor}` hay emojis (pares sustitutos), el cursor queda corrido. Contar con `StrPut`/parse por grafemas o documentar la limitación.

### 🟡 1.12 Tab/Enter/Esc secuestrados mientras el menú está visible
Con el menú abierto, Tab/Enter/Esc son hotkeys globales que NO llegan a la aplicación. Si el menú apareció sin querer (caso URL del 1.4), el Tab del usuario "desaparece". Considerar: si `typed = ""` (aún no filtró nada), dejar pasar Tab/Enter y solo capturarlos cuando haya intención clara.

---

## 2. Robustez y calidad de código

- ✅ HECHO — 🟠 **2.1 Sin manejo global de errores**
  > `OnError(LogError)`: registra fecha, mensaje y línea en `midword.log` (agregado a `.gitignore`) y muestra TrayTip amable en vez del diálogo crudo.
- ✅ HECHO — 🟠 **2.2 Monitor múltiple**
  > Helper `MonWork(x, y, …)` con `MonitorGetWorkArea`: el menú y los 2 submenús se posicionan dentro del monitor donde está el caret (fallback al primario).
- 🟠 **2.3 Caret en navegadores/Electron**: `CaretGetPos` falla en Chrome/WhatsApp Web y cae al mouse. Integrar detección por UIA/MSAA (patrón `TextPattern`) para posicionar junto al cursor real.
- 🟡 **2.4 Reconstrucción total del menú por tecla**: `BuildMenu()` destruye y recrea la GUI en cada pulsación → parpadeo y costo. Reusar la ventana actualizando textos/colores de las filas.
- 🟡 **2.5 `HoverWatch` con polling de 80 ms**: sustituible por `OnMessage(WM_MOUSEMOVE)` en los controles; menos CPU y respuesta inmediata.
- 🟡 **2.6 Ancho de texto estimado con `StrLen * 9`**: falla con fuentes/DPI distintos. Medir texto real (`Gui.AddText` + `GuiControlGet Pos`, o `DrawText` con `DT_CALCRECT`).
- 🟡 **2.7 Estado global disperso**: ~40 variables globales. Sin romper el "un solo archivo", agrupar en clases (`class SuggestMenu`, `class SubMenu`, `class Manager`, `class Config`) mejora mantenibilidad y evita bugs de `global` olvidados.
- 🟡 **2.8 Sin pruebas**: extraer el parser (`LoadShortcuts`/`ParseLevel`/`SerializeAtajo`/`AutoTok`) a funciones puras y escribir un `tests.ahk` que corra asserts en CI (roundtrip parse→serialize→parse).
- 🔵 **2.9 IME / teclados con teclas muertas**: InputHook + tildes con teclas muertas funciona en layout latinoamericano, pero con IME (chino/japonés) no captura. Documentar como limitación conocida.
- ✅ HECHO — 🔵 **2.10 Constante de versión**
  > `VERSION := "1.3.0"` + directivas `;@Ahk2Exe-SetVersion/SetName/SetDescription/SetCopyright` (el exe compilado lleva metadatos) + versión visible en el tooltip del ícono de bandeja.

---

## 3. UX del menú de sugerencias

- ✅ HECHO — 🟠 **3.1 Pausar/activar**
  > Toggle "Pausar (no sugerir)" en la bandeja (detiene el InputHook y limpia el estado) + hotkey opcional `hotkey_pausa` en `midword.ini` + tooltip del icono cambia a "(en pausa)". Pendiente menor: icono gris dedicado.
- ✅ HECHO — 🟠 **3.2 Deshacer expansión**
  > Backspace dentro de los 10 s posteriores a una expansión borra el texto insertado (contando por code points, no unidades UTF-16 — los emojis se borran bien) y restaura lo escrito (`//atajo`). Se cancela al escribir, hacer clic o mover el caret. No aplica a atajos con `{cursor}` ni de archivo.
- 🟡 **3.3 Coincidencia sin tildes**: buscar `//numero` no encuentra un atajo cuyo texto dice "número". Normalizar con el mismo mapa de `AutoTok` al comparar.
- 🟡 **3.4 Búsqueda difusa**: coincidencia por subsecuencia (`//grc` → `gracias`) además de prefijo/contiene.
- 🟡 **3.5 Orden por frecuencia de uso**: contar usos por atajo (persistido) y rankear las coincidencias; los más usados primero.
- ✅ HECHO — 🟡 **3.6 Lista negra/blanca de aplicaciones**
  > `apps_excluidas=Code.exe|WindowsTerminal.exe` en `midword.ini`; `AppExcluded()` compara el exe de la ventana activa al inicio de `UpdateSuggestions` (bloquea menú y expansión instantánea).
- 🟡 **3.7 Tema oscuro del menú**: la paleta es fija (crema). Detectar el tema de Windows (`AppsUseLightTheme`) y ofrecer paleta oscura.
- 🟡 **3.8 Truncado visual sin elipsis**: la columna del trigger se corta a `TW=200px` sin "…". Añadir elipsis o tooltip.
- 🔵 **3.9 Scroll en el menú**: con más de 10 coincidencias solo dice "sigue escribiendo… (+N)". Permitir bajar con ↓ más allá de la fila 10 (paginado o scroll real).
- 🔵 **3.10 Sombra de la ventana**: al ser `-Caption` no hay sombra DWM; en Win11 se puede pedir esquina redondeada nativa (`DWMWA_WINDOW_CORNER_PREFERENCE=33`) y sombra, en vez de `WinSetRegion` (que produce bordes dentados).
- 🔵 **3.11 Números rápidos**: `Alt+1..9` (o `Ctrl+número`) para insertar la fila N sin flechas.
- 🔵 **3.12 Vista previa completa**: tooltip o panel al costado con el texto completo del atajo seleccionado (hoy se corta a 56 chars).

---

## 4. Gestor de atajos

- 🟠 **4.1 Sin reordenar ni secciones**: el gestor siempre agrega al final; las secciones `# ── Ventas ──` del archivo no se ven ni se pueden elegir. Mostrar secciones como grupos en la lista y permitir "guardar en sección X" y mover arriba/abajo.
- ✅ HECHO — 🟠 **4.2 Aviso de conflicto instantáneo**
  > Al guardar un atajo instantáneo cuyo nombre es prefijo de otro atajo existente, el gestor avisa cuál chocaría y pide confirmación.
- 🟡 **4.3 Ventana no redimensionable** (800×516 fijo) y sin `Esc` para cerrar. Con muchos atajos la lista de 270px queda corta.
- 🟡 **4.4 Indicador de cambios sin guardar**: se puede cerrar o cambiar de selección con el formulario editado y se pierde todo sin aviso.
- 🟡 **4.5 Duplicados al importar**: `DoImport` no compara contra los atajos existentes; importa `gracias=` aunque ya exista. Mostrar preview con conflictos (nuevo/duplicado/actualiza) antes de confirmar.
- 🟡 **4.6 Botón Exportar**: para llevar atajos a otra PC (copia el archivo o las líneas seleccionadas al portapapeles). El caso "copiado de otra PC" ya se menciona en el código, pero solo existe la mitad (importar).
- 🔵 **4.7 Probar atajo desde el gestor**: botón "Probar" que expande en un Edit de prueba, con variables resueltas.
- 🔵 **4.8 Multi-selección para eliminar** varios de una vez.
- ✅ HECHO — 🔵 **4.9 Atajo global para abrir el gestor**
  > `hotkey_gestor=^!g` en `midword.ini` (opcional, sin default para no chocar con otras apps).
- 🔵 **4.10 Inconsistencia docs**: `LEEME.txt` menciona botones "➕ Nuevo", "💾 Guardar", "📋 Importar" con emoji; los reales dicen "+ Nuevo", "Guardar", "Importar desde IA". Alinear.

---

## 5. Formato de `atajos.txt` y variables

- ✅ HECHO — 🟠 **5.1 Prefijo configurable**
  > `prefijo=;;` en `midword.ini` (default `//`). El menú, la expansión, el borrado y la etiqueta del gestor usan `PREFIX` en todos lados.
- 🟡 **5.2 Más variables**: `{portapapeles}` (inserta lo copiado dentro de la plantilla), `{fecha+7}` / `{fecha-1}` (aritmética de fechas para plazos de entrega — muy útil para RedactorIA), `{input:Nombre del cliente}` (mini-prompt al expandir), `{mayus:...}`, variables definidas por el usuario (`$yape=999...` reutilizable en varios atajos).
- 🟡 **5.3 Escapes incompletos**: solo existe `\n`. No hay forma de insertar un `\n` literal, ni `\t`, ni `{1}` literal en un texto de grupo. Definir `\\n`, `\t`, `\{`.
- 🟡 **5.4 `archivo:` múltiple**: `CF_HDROP` soporta lista de archivos; permitir `archivo:ruta1|ruta2` para adjuntar varios de un golpe (catálogo + lista de precios).
- 🟡 **5.5 Validación al cargar**: triggers con espacios internos o caracteres imposibles de tipear pasan el parser pero jamás matchearán (el menú los oculta al escribir por el check `\s`). Avisarlos junto con las líneas sin `=`.
- 🔵 **5.6 BOM/codificación**: si el usuario guarda el archivo como ANSI desde un editor viejo, las tildes se rompen. Escribir con BOM UTF-8 (`UTF-8-RAW` vs `UTF-8` en AHK) y detectar/convertir al leer.
- 🔵 **5.7 Grupos de 3+ niveles** (hoy silenciosamente rotos, ver 1.8): o soportarlos de verdad generalizando `OpenSub` (recursivo), o rechazarlos con aviso.
- 🔵 **5.8 Texto con formato (rich text)**: colocar HTML/RTF en el portapapeles además de texto plano, para que en Word/Gmail se pegue con negritas. Complejo pero factible (formatos `CF_HTML`/`Rich Text Format`).
- 🔵 **5.9 Modo tecleo por app**: algunas apps no aceptan Ctrl+V (terminales, RDP, campos "seguros"). Sintaxis `atajo=teclear:texto` o config por app que use `SendText` en lugar de pegar.

---

## 6. Scripts, instalación y distribución

- ✅ HECHO — 🟠 **6.1 Rutas absolutas `D:\atajos` hardcodeadas**
  > `recompilar.ps1` usa `$PSScriptRoot` e `instalar_inicio.bat` usa `%~dp0`; README/LEEME actualizados (ya no piden editar rutas).
- ✅ HECHO — 🟠 **6.2 "Iniciar con Windows" desde la app**
  > Nueva opción con check en el menú de la bandeja (crea/borra `Startup\Midword.lnk` vía `FileCreateShortcut`); también se agregó `desinstalar_inicio.bat`.
- ✅ HECHO — 🟠 **6.3 CI con GitHub Actions**
  > `.github/workflows/ci.yml`: job `validar` (descarga AutoHotkey v2 y corre `/validate` en cada push/PR) y job `release` (en tags `v*` compila con Ahk2Exe y adjunta `Midword.exe` + `SHA256.txt` al Release). OJO al pushear: si el token de gh no tiene scope `workflow`, subir el yml aparte.
- ✅ HECHO — 🟡 **6.4 `recompilar.ps1` frágil**
  > Ahora: valida que AutoHotkey y Ahk2Exe existan, compila a `Midword.new.exe` temporal, espera el archivo con timeout de 30 s (sin sleep ciego), recién entonces mata el proceso y reemplaza el exe; se eliminó el kill del proceso legado `Atajos`.
- ⏭️ OMITIDO — 🟡 **6.5 Firma de código / SmartScreen**
  > La parte automatizable ya está: el CI publica `SHA256.txt` con cada release. El certificado de firma y el whitelisting de Microsoft requieren cuenta/pago externos — decisión del dueño del proyecto.
- ⏭️ OMITIDO — 🟡 **6.6 Winget / Scoop / Chocolatey**
  > Requiere submission a repositorios externos (microsoft/winget-pkgs, bucket de Scoop) con revisión humana; fuera del alcance del loop local.
- 🔵 **6.7 Buscador de actualizaciones**: opción de bandeja "Buscar actualización" que consulte `api.github.com/repos/brolyroly007/midword/releases/latest` y avise si hay versión nueva.
- 🔵 **6.8 Instalador opcional** (Inno Setup): para el público no técnico que no sabe "descargar un exe y crear acceso directo". Mantener el zip portable como opción A.

---

## 7. Repositorio, docs y comunidad

- ✅ HECHO — 🟠 **7.1 GIF de demo pendiente**
  > `demo.gif` generado desde `midword-demo-linkedin.mp4` con ffmpeg (520 px, 8 fps, paleta de 96 colores, 3.3 MB) e insertado en el README donde estaba el placeholder.
- ✅ HECHO (badges) — 🟡 **7.2 Badges y metadatos**
  > Badges de release, descargas, CI y licencia en el README. Los topics y el social preview se configuran en GitHub al pushear (manual o `gh repo edit --add-topic autohotkey --add-topic text-expander …`).
- ✅ HECHO — 🟡 **7.3 CHANGELOG.md**
  > Creado con las 3 versiones publicadas y una sección "[Sin publicar]" con todo lo de esta tanda de mejoras.
- 🟡 **7.4 README en inglés** (`README.en.md`): el nicho hispano es el foco, pero un text expander gratis MIT tiene público global; duplica el alcance con una hora de trabajo.
- 🟡 **7.5 Verificar Discussions**: `config.yml` enlaza a Discussions; si no está habilitado en el repo, el enlace da 404.
- 🔵 **7.6 Comparativa honesta**: sección "¿Por qué Midword y no espanso/Beeftext/PhraseExpress?" — el diferencial real es el menú de autocompletado visual + submenús en cascada + español + prompt de IA incluido.
- 🔵 **7.7 Wiki o docs/ con recetas**: "atajos para ventas por WhatsApp", "atajos para soporte", "atajos académicos" — contenido SEO que además alimenta el marketing de RedactorIA.
- 🔵 **7.8 Historial de git**: verificar que el exe/mp4 no quedaron en commits viejos inflando el clone (el rebrand tocó binarios); si pesan, `git filter-repo` antes de que el repo crezca.

---

## 8. ✅ HECHO (salvo `tema`) — Opciones y personalización (`midword.ini`)

> Implementado: `midword.ini` opcional con sección `[opciones]` y helper `OptGet()`. Documentado en LEEME.txt y en el encabezado del script.

| Opción | Default | Estado |
|---|---|---|
| `prefijo` | `//` | ✅ |
| `min_caracteres` | 0 | ✅ |
| `max_filas` | 10 (3–20) | ✅ |
| `delay_pegar` | 250 ms | ✅ |
| `delay_archivo` | 1200 ms | ✅ |
| `tema` | claro | ⏳ pendiente, va con el ítem 3.7 (tema oscuro) |
| `apps_excluidas` | — | ✅ |
| `sonido` | 0 | ✅ (`sonido=1` → bip al insertar) |
| `hotkey_pausa`, `hotkey_gestor` | — | ✅ |

---

## 9. Ideas ambiciosas 🚀 (las "imposibles")

- **9.1 Sincronización en la nube**: mismo `atajos.txt` en varias PCs. Versión "posible hoy": documentar que la carpeta puede vivir en Drive/Dropbox y añadir un parámetro `Midword.exe /config ruta`. Versión imposible: backend propio con cuentas y merge de conflictos.
- **9.2 Midword para equipos**: una librería de atajos compartida del negocio (el jefe edita, los vendedores reciben). Base de un modelo de pago — encaja con el perfil de clientes de RedactorIA (negocios que venden por WhatsApp en Perú).
- **9.3 macOS / Linux**: AHK no existe fuera de Windows; sería reescritura completa (Rust + rdev/enigo, o contribuir un frontend visual a espanso). Solo si el proyecto despega.
- **9.4 Android (teclado IME)**: donde de verdad viven las ventas por WhatsApp en Perú. Un teclado Android con los mismos atajos y sintaxis compartida sería el salto de producto más valioso — y un proyecto entero aparte (Kotlin, InputMethodService). Sinergia directa con BiPe Alerta.
- **9.5 IA en línea**: además del prompt manual, un botón "Redactar con IA" que llame a una API (con la key del usuario) para generar la respuesta según el contexto copiado. Contradice el "sin internet" del pitch — debería ser opt-in absoluto.
- **9.6 Sugerencias por contexto**: leer (vía UIA) el último mensaje recibido en WhatsApp Web y sugerir el atajo más probable sin escribir `//`. Técnicamente fascinante, éticamente delicado, frágil ante cambios de UI.
- **9.7 Marketplace de paquetes**: paquetes de atajos por rubro (delivery, academias, inmobiliarias) instalables con un clic desde el gestor. Requiere hosting + moderación.
- **9.8 Estadísticas de conversión**: contar qué respuestas llevan a venta (integrado con BiPe Alerta detectando el Yape posterior). Cruce natural entre tus dos productos.
- **9.9 Expansión con voz**: dictar "midword confirma veinte" y que inserte `//con20`. Requiere STT residente; hoy no justifica el peso.

---

## 10. Resumen priorizado (si solo haces 10 cosas)

1. ✅ Guardado atómico + respaldos rotativos (1.2) — riesgo real de perder datos del usuario.
2. ✅ No abrir el menú al escribir URLs (1.4) + `min_caracteres` (8).
3. ✅ Arreglar `!` en grupos de 2 niveles (1.1).
4. ✅ Rutas relativas en `.bat`/`.ps1` + "Iniciar con Windows" desde la bandeja (6.1, 6.2).
5. ✅ Pausar/activar desde la bandeja (3.1).
6. ✅ GIF de demo en el README (7.1) — costo mínimo, máximo impacto.
7. ✅ CI de validación + release automático (6.3).
8. ✅ Lost-update del gestor con ediciones externas (1.3).
9. ✅ Prefijo y delays configurables (5.1, 8).
10. ⏭️ Winget/Scoop (submission externa) — el hash en releases sí quedó ✅ vía CI (6.5, 6.6).
