<div align="center">

<img src="logo.png" width="80" alt="Midword">

# Midword

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="branding/midword-wordmark-animated-dark.svg">
  <img src="branding/midword-wordmark-animated.svg" width="300" alt="mid|word — tu texto se completa solo">
</picture>

[![Release](https://img.shields.io/github/v/release/brolyroly007/midword?label=release&color=6A9E8C)](../../releases/latest)
[![Descargas](https://img.shields.io/github/downloads/brolyroly007/midword/total?label=descargas&color=4A7C5F)](../../releases)
[![CI](https://github.com/brolyroly007/midword/actions/workflows/ci.yml/badge.svg)](../../actions)
[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-blue)](LICENSE)

**Expansor de texto global para Windows, con menú de autocompletado estilo WhatsApp.**

Escribe `//atajo` en cualquier aplicación —WhatsApp Web, Word, Telegram, tu navegador— y aparece un menú flotante con tus frases guardadas. Tab o Enter, y el texto completo se inserta al instante.

*¿Respondes lo mismo 50 veces al día? Esto es para ti.*

</div>

---

<div align="center">
<img src="demo.gif" width="520" alt="Demo: escribir //atajo abre el menú de sugerencias y Tab inserta el texto completo">
</div>

## ✨ Qué hace

- **Autocompletado en cualquier app**: escribe `//` + letras y aparecen las sugerencias junto al cursor. También busca dentro del texto de los atajos, no solo en el nombre.
- **Grupos desglosables en cascada**: `//con` muestra una fila que al pasar el mouse (o `→`) se abre en submenús — por ejemplo montos de 5 a 50 soles, o formato → cantidad de páginas. Hasta 2 niveles.
- **Variables dinámicas**: `{fecha}`, `{hora}`, `{dia}`, `{fecha_larga}` se reemplazan al insertar; `{cursor}` deja el cursor donde tú quieras para completar un dato.
- **Expansión instantánea**: los atajos marcados con `!` se insertan apenas terminas de escribirlos, sin Tab.
- **Inserción por portapapeles**: instantánea incluso con textos largos, los saltos de línea **no** envían el mensaje en WhatsApp, y lo que tenías copiado se restaura solo.
- **Gestor visual**: clic en el ícono de la bandeja y administra todo desde una ventana — crear, editar, duplicar, eliminar, con vista previa en vivo y sin tocar sintaxis.
- **Generación con IA**: incluye `PROMPT_PARA_IA.txt` — pégalo en ChatGPT/Claude/Gemini, describe tu negocio, e importa los atajos que te genere con un clic.
- Ligero de verdad: un solo exe (~1 MB), sin instalación, sin internet, tus datos en un `.txt` tuyo.

## 📦 Instalación

**Opción A — Ejecutable (recomendada):**

1. Descarga `Midword.exe` desde [Releases](../../releases).
2. Ponlo en una carpeta (ej. `C:\atajos`) y ábrelo. Aparece su ícono junto al reloj.
3. Escribe `//con` en cualquier app para probar.
4. Para que arranque con Windows: activa **"Iniciar con Windows"** en el menú de la bandeja (clic derecho en el ícono), o ejecuta `instalar_inicio.bat` una vez.

**Opción B — Desde el código fuente:**

1. Instala [AutoHotkey v2](https://www.autohotkey.com/).
2. Clona este repo y haz doble clic en `midword.ahk`.

En el primer arranque se crea `atajos.txt` con ejemplos (o copia `atajos.ejemplo.txt` como `atajos.txt` y personalízalo).

## 🚀 Uso

| Acción | Cómo |
|---|---|
| Buscar un atajo | escribe `//` + primeras letras |
| Elegir | `↑` `↓` o el mouse |
| Desglosar un grupo | pasar el mouse o `→` (`←` regresa) |
| Insertar | `Tab`, `Enter`, o clic |
| Cancelar | `Esc` |
| Ver todos los atajos | botón `☰ ver todos` o ícono de la bandeja |
| Gestionar (crear/editar) | clic en el ícono de la bandeja |

## 📝 Sintaxis de `atajos.txt`

```ini
# atajo simple
gracias=¡Muchas gracias! Cualquier consulta me escribes.

# instantáneo (se inserta sin Tab)
ok!=Recibido, lo reviso y te confirmo en breve.

# grupo desglosable: //con → submenú con 5, 10, 15…  ({1} = opción elegida)
con[5|10|15|20]=para confirmar es necesario un adelanto de {1} soles.

# dos niveles + etiquetas: //mon → formato → páginas  (token:Etiqueta)
mon[apa:APA 7|ieee:IEEE][10:10 páginas|20:20 páginas]=Redacta en formato {1}, de {2}.

# variables
cita=Nos vemos el {dia} {fecha} a las {hora}
precio=El costo es S/ {cursor} e incluye revisiones.
```

Los cambios se recargan solos (~3 s después de guardar). Usa `\n` para saltos de línea.

## 🤖 Generar atajos con IA

Copia el contenido de [`PROMPT_PARA_IA.txt`](PROMPT_PARA_IA.txt), pégalo en cualquier IA, describe tu negocio al final, y pega el resultado en el gestor (**Importar desde IA**) o directo en `atajos.txt`.

## 🛡️ ¿Tu antivirus marca el exe?

Es un **falso positivo** común con ejecutables compilados de AutoHotkey (el compilador empaqueta un intérprete, y algunos antivirus desconfían por costumbre). El código fuente completo está en este repo — puedes leerlo, ejecutar `midword.ahk` directamente, o compilarlo tú mismo con `recompilar.ps1` (requiere AutoHotkey v2 instalado).

## 🔧 Compilar

```powershell
powershell -ExecutionPolicy Bypass -File recompilar.ps1
```

Valida, compila con Ahk2Exe (base AutoHotkey v2 de 64 bits) y reinicia el programa.

## Licencia

[MIT](LICENSE) — úsalo, modifícalo y compártelo libremente.
