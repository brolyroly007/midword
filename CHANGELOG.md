# Changelog

Novedades de Midword por versión. Formato inspirado en [Keep a Changelog](https://keepachangelog.com/es/).

## [1.3.0] — 2026-07-07

### Corregido
- El `!` (expansión instantánea) se perdía en grupos de 2 niveles.
- Guardado atómico de `atajos.txt` (temp + rename): un fallo a medias ya no puede destruir tus atajos; además se guardan respaldos rotativos en `respaldos\` (los 10 últimos).
- Escribir una URL (`https://`) o una ruta ya no abre el menú: el prefijo solo activa al inicio o tras un separador.
- El gestor ya no duplica ni pisa cambios si editas `atajos.txt` a mano mientras está abierto (la línea en edición se reubica por contenido).
- Fuga de memoria al pegar archivos si otro proceso tenía el portapapeles abierto (ahora con reintentos).
- Ctrl+Backspace y Ctrl+A/C/V ya no desincronizan el borrado al expandir.
- Los grupos con más de 2 niveles y las opciones con token repetido ahora se avisan al cargar (antes fallaban en silencio).
- El menú y los submenús se posicionan correctamente en configuraciones multi-monitor.

### Agregado
- `midword.ini` opcional: `prefijo`, `min_caracteres`, `max_filas`, `delay_pegar`, `delay_archivo`, `apps_excluidas`, `sonido`, `hotkey_pausa`, `hotkey_gestor`.
- Menú de bandeja: **Pausar (no sugerir)** e **Iniciar con Windows** (con check).
- Deshacer: un Backspace justo después de una expansión la revierte y restaura lo que habías escrito.
- El gestor avisa si un atajo instantáneo es prefijo de otro atajo (se dispararía antes de poder escribir el otro) y si dos opciones de un nivel generan el mismo token.
- Errores de runtime a `midword.log` con aviso amable (antes: diálogo crudo de AHK).
- `desinstalar_inicio.bat`; `instalar_inicio.bat` ya no requiere editar rutas.
- CI en GitHub Actions: valida la sintaxis en cada push y publica `Midword.exe` + `SHA256.txt` en cada tag `v*`.
- GIF de demo en el README y versión visible en el tooltip del ícono.

## [1.2.0] — 2026-06-10
- Rebrand: Atajos pasa a llamarse **Midword**; nuevo logo m|w, wordmark animado y assets.
- Guía de contribución (`CONTRIBUTING.md`) y plantillas de issues.

## [1.1.0] — 2026-06-10
- Atajos de archivo (sintaxis `archivo:`): imágenes, videos y PDF se adjuntan en WhatsApp/Telegram/Gmail o se insertan en Word.
- Fix: constante de color inexistente en el botón de archivo del gestor.

## [1.0.0] — 2026-06-10
- Versión inicial: expansor global con menú de autocompletado, grupos desglosables de hasta 2 niveles, variables `{fecha}` `{hora}` `{dia}` `{fecha_larga}` `{cursor}`, expansión instantánea con `!`, gestor visual e importación de atajos generados por IA.
