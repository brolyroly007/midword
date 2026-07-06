# Cómo contribuir

¡Gracias por tu interés en mejorar Midword! Cualquier aporte es bienvenido: reportar bugs, proponer ideas o enviar código.

## Reportar un bug o proponer una idea

Abre un [issue](../../issues/new/choose) usando la plantilla que corresponda. Mientras más detalle des (versión de Windows, aplicación donde ocurre, pasos para reproducir), más rápido se puede resolver.

## Enviar código (Pull Request)

1. Haz **fork** del repositorio y clónalo.
2. Crea una rama descriptiva: `git checkout -b fix/menu-no-cierra`
3. Haz tus cambios y pruébalos (ver abajo).
4. Envía un Pull Request explicando **qué** cambia y **por qué**.

Los PRs pequeños y enfocados se revisan más rápido que los grandes.

## Entorno de desarrollo

- **Requisito:** [AutoHotkey v2](https://www.autohotkey.com/) (el script no es compatible con v1).
- El programa completo vive en un solo archivo: `midword.ahk`.
- Para probar: cierra la instancia en ejecución (icono en bandeja → Salir) y ejecuta `midword.ahk` directamente con doble clic.

### Validar sintaxis antes de enviar

```powershell
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut /validate midword.ahk
```

Si no imprime nada, la sintaxis es válida.

### Trampas conocidas de AHK v2

- No uses `buffer` como nombre de variable (colisiona con la clase `Buffer`).
- `{base: x}` en un literal de objeto cambia el prototipo y falla en tiempo de ejecución aunque pase la validación — usa otro nombre de propiedad.
- Los errores de runtime no aparecen en `/validate`: prueba siempre ejecutando el script.
- El `InputHook` no captura escritura por composición (IME chino/japonés/coreano): es una limitación conocida, no intentes "arreglarla" con hooks extra.
- Corre `AutoHotkey64.exe midword.ahk --selftest` antes de enviar un PR (también lo corre el CI).

## Estilo de código

- Sigue el estilo del archivo existente: nombres descriptivos en inglés para funciones (`UpdateSuggestions`, `InsertText`), comentarios en español.
- Colores y constantes de tema van al bloque de paleta al inicio del archivo (`CLR_*`).
- No agregues dependencias externas: el proyecto es un solo `.ahk` portable.

## Atajos de ejemplo

`atajos.txt` es personal y está en `.gitignore`. Si tu cambio afecta el formato del archivo de atajos, actualiza también `atajos.ejemplo.txt` y, si aplica, la gramática en `PROMPT_PARA_IA.txt`.
