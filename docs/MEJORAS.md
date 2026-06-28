# midword — Análisis y Mejoras

> Expansor de texto global para Windows. Escribes `//atajo` en cualquier app y aparece un menú flotante con sugerencias, grupos desplegables y variables dinámicas.
> Repo: https://github.com/brolyroly007/midword

---

## 1. Radiografía

| Aspecto | Detalle |
|---------|---------|
| **Lenguaje** | AutoHotkey v2.0 (archivo único `midword.ahk`, ~1.314 líneas) |
| **Build** | `Ahk2Exe` → `Midword.exe` (~1 MB), script `recompilar.ps1` |
| **Dependencias** | Ninguna externa (DLL calls nativos de Windows) |
| **Almacenamiento** | `atajos.txt` (datos del usuario) |
| **Tests** | ❌ Ninguno |
| **CI/CD** | ❌ Ninguno (validación manual con `/validate`) |
| **Licencia** | MIT |

**Fortalezas:** UX muy pulida (hover inteligente a 80ms, posicionamiento que evita salirse de pantalla), preserva el portapapeles original, documentación clara (README + `PROMPT_PARA_IA.txt`), arquitectura modular dentro del archivo.

**Debilidades clave:**
- Sin tests → cualquier cambio en el parsing/regex de atajos es frágil.
- Búsqueda **O(n)** con doble pasada (`UpdateSuggestions`, líneas ~305-325) → lag perceptible con >500 atajos.
- *Magic numbers* esparcidos (dimensiones, timeouts) → difícil de mantener/temar.
- Sin CI ni releases reproducibles.
- Manejo de errores pobre (carga vacía silenciosa si `atajos.txt` se corrompe).

---

## 2. 🎯 Mejora consistencial

**Separar "datos" de "presentación": una capa de modelo de atajos con búsqueda indexada y testeada.**

Hoy el parsing, la búsqueda y el render del menú están entrelazados en el mismo flujo. La mejora coherente es extraer un módulo lógico (parser + índice de búsqueda + serializador) que sea **probable sin abrir la GUI**. Esto:

- Habilita tests unitarios reales (parsing de grupos `mon[apa|ieee][10|20]`, variables `{fecha}`, escapes, round-trip serializar→releer).
- Permite cambiar la búsqueda de lineal a un **índice por prefijo (Trie/Map)** sin tocar la UI.
- Reduce el riesgo de los refactors futuros.

Es "consistencial" porque ataca la raíz (acoplamiento + falta de testabilidad) en lugar de un síntoma puntual.

---

## 3. 🚀 Supermejoras (ordenadas por impacto)

| # | Mejora | Por qué | Esfuerzo |
|---|--------|---------|----------|
| 1 | **Suite de tests** del parser/búsqueda/serializador | Da confianza para refactorizar; protege contra regresiones | Medio-Alto |
| 2 | **Búsqueda indexada** (Trie / índice invertido + caché) | UX fluida con miles de atajos | Medio |
| 3 | **Tema centralizado** (`THEME` con dimensiones/colores/timeouts) | Habilita modo oscuro y densidad; elimina magic numbers | Bajo |
| 4 | **CI/CD con GitHub Actions** (validar → compilar → release con hash) | Releases reproducibles, onboarding de contribuidores | Medio |
| 5 | **Manejo de errores + logging** (fallback si `atajos.txt` corrupto, `.log` de debug, timeout configurable en `ClipWait`) | Robustez en casos límite | Medio |
| 6 | **Modo oscuro automático** (detectar preferencia de Windows vía `dwmapi`) | UX moderna | Bajo |
| 7 | **Snapshot/recuperación** de `atajos.txt` ante crash durante `FileAppend` | Seguridad de datos del usuario | Bajo |
| 8 | **Sincronización opcional** (export/import cifrado o vía Git/Drive) | Portar atajos entre máquinas | Medio |

---

## 4. 🏁 Metas / Roadmap

- **Corto plazo (2-3 semanas):** Tema centralizado + CI básico (validar sintaxis en cada PR) + manejo de errores en `LoadShortcuts`.
- **Medio plazo (1-2 meses):** Extraer la capa de datos, escribir la suite de tests, migrar a búsqueda indexada.
- **Largo plazo (Q4 2026):** Modo oscuro, recuperación ante crash, y sincronización entre dispositivos. Publicar v2.0.

### Métricas de éxito
- ✅ CI verde en cada push.
- ✅ Búsqueda < 16ms (1 frame) con 2.000 atajos cargados.
- ✅ Cobertura de tests ≥ 60% en la capa de datos.
- ✅ 0 pérdidas de `atajos.txt` reportadas tras introducir el snapshot.

---

## 5. 💻 Snippet de referencia

**Tema centralizado** (elimina los *magic numbers* y habilita modo oscuro), en AutoHotkey v2:

```autohotkey
; --- antes: dimensiones esparcidas por todo el archivo ---
; W := 620, HH := 30, RH := 36 ...

; --- después: un solo objeto THEME ---
global THEME := {
    MENU_WIDTH: 620,
    HEADER_HEIGHT: 30,
    ROW_HEIGHT: 36,
    HOVER_TIMER: 80,
    SLEEP_PASTE_TEXT: 250,
    colors: Map(
        "bg",     "0xF7F4ED",
        "accent", "0x6F9C81",
        "ink",    "0x1F1E1B"
    )
}
; uso:  W := THEME.MENU_WIDTH
```

**Búsqueda indexada** (sustituye la doble pasada O(n) por un índice por prefijo):

```autohotkey
; al cargar atajos.txt, construye el índice una sola vez
BuildIndex(shortcuts) {
    idx := Map()
    for trig, _ in shortcuts {
        prefix := SubStr(trig, 1, 2)
        if !idx.Has(prefix)
            idx[prefix] := []
        idx[prefix].Push(trig)
    }
    return idx
}
; al teclear, solo miras el bucket del prefijo, no todo el Map
```

