<div align="center">

<img src="logo.png" width="80" alt="Midword">

# Midword

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="branding/midword-wordmark-animated-dark.svg">
  <img src="branding/midword-wordmark-animated.svg" width="300" alt="mid|word — your text completes itself">
</picture>

[![Release](https://img.shields.io/github/v/release/brolyroly007/midword?label=release&color=6A9E8C)](../../releases/latest)
[![Downloads](https://img.shields.io/github/downloads/brolyroly007/midword/total?label=downloads&color=4A7C5F)](../../releases)
[![CI](https://github.com/brolyroly007/midword/actions/workflows/ci.yml/badge.svg)](../../actions)
[![MIT License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**Global text expander for Windows with a WhatsApp-style autocomplete menu.**

Type `//shortcut` in any application — WhatsApp Web, Word, Telegram, your browser — and a floating menu appears with your saved phrases. Tab or Enter, and the full text is inserted instantly.

*Español: [README.md](README.md)*

</div>

---

<div align="center">
<img src="demo.gif" width="520" alt="Demo: typing //shortcut opens the suggestion menu and Tab inserts the full text">
</div>

## ✨ Features

- **Autocomplete anywhere**: type `//` + letters and suggestions appear next to your caret. Searches inside the text of your snippets too — accent-insensitive, with fuzzy matching (`//grc` finds `gracias`), ranked by how often you use each one.
- **Cascading groups**: `//dep` can unfold into submenus (e.g. amounts, formats → page counts). Up to 2 levels.
- **Dynamic variables**: `{fecha}` (date), `{hora}` (time), `{fecha+7}` (date 7 days from now), `{portapapeles}` (current clipboard), `{input:Question}` (prompt on expand), `{$var}` (your own reusable variables), `{cursor}` (leave the caret anywhere).
- **Instant expansion**: shortcuts marked with `!` insert as soon as you finish typing them — and a quick Backspace undoes the expansion.
- **File shortcuts**: `logo=archivo:C:\logo.png` pastes/attaches files (multiple with `|`) into WhatsApp, Telegram, Word or Gmail.
- **Visual manager**: create, edit, reorder and organize shortcuts in sections from a tray-icon window — with live preview, duplicate detection and export/import.
- **AI generation**: paste `PROMPT_PARA_IA.txt` into ChatGPT/Claude/Gemini, describe your business, and import the generated shortcuts in one click.
- **Configurable**: optional `midword.ini` — custom prefix, dark theme (or auto), excluded apps, paste delays, hotkeys.
- Truly lightweight: a single ~1 MB exe, no installer, no internet, your data in a plain `.txt` you own.

## 📦 Install

1. Download `Midword.exe` from [Releases](../../releases) (SHA-256 published per release).
2. Put it in a folder and run it. Its icon appears next to the clock.
3. Type `//con` in any app to try it.
4. To start with Windows: enable **"Iniciar con Windows"** from the tray menu.

Or run from source: install [AutoHotkey v2](https://www.autohotkey.com/) and double-click `midword.ahk`.

> **Antivirus flags the exe?** It's a common false positive with compiled AutoHotkey binaries. The full source is in this repo — read it, run the `.ahk` directly, or build it yourself with `recompilar.ps1`.

## 🚀 Usage

| Action | How |
|---|---|
| Search a shortcut | type `//` + first letters |
| Choose | `↑` `↓` or mouse |
| Unfold a group | hover or `→` (`←` goes back) |
| Insert | `Tab`, `Enter`, or click |
| Undo an expansion | `Backspace` right after |
| Cancel | `Esc` |
| Manage (create/edit) | click the tray icon |

## 📝 `atajos.txt` syntax

```ini
# simple shortcut
gracias=¡Muchas gracias! Cualquier consulta me escribes.

# instant (inserts without Tab)
ok!=Recibido, lo reviso y te confirmo en breve.

# unfoldable group ({1} = chosen option)
con[5|10|15|20]=para confirmar es necesario un adelanto de {1} soles.

# two levels + labels (token:Label)
mon[apa:APA 7|ieee:IEEE][10:10 páginas|20:20 páginas]=Redacta en formato {1}, de {2}.

# your own variables
$yape=999 999 999
pago=Yapea al {$yape} y me avisas 🙌
```

Changes reload automatically (~3 s after saving). The UI and docs are in Spanish — the target audience is Spanish-speaking sellers and freelancers — but the engine is language-agnostic.

## License

[MIT](LICENSE)
