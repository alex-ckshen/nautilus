# Nautilus vs Grok Build — feature map (Path A: PowerShell)

Source: xai-org/grok-build docs (`user-guide/03-keyboard-shortcuts.md`, `04-slash-commands.md`) + pager actions/slash registry.
Nautilus stays pure PowerShell; we port *behaviour*, not Rust crates.

## Already in Nautilus (through 0.4.2.0)

| Area | Status |
|------|--------|
| `/` slash menu with type-to-filter dropdown | 0.3.47 |
| Grouped `/` categories (Session / Clipboard / Theme & UI / Help) | 0.4.0.2 |
| No bottom model/theme/connection status footer | 0.4.0.2 |
| Complete 3-line ASCII prompt frame; Big5-safe separators | 0.4.0.3 |
| Larger centered `/` slash modal (full borders) | 0.4.0.3 |
| `/copycode` + Ctrl+Shift+C fence copy | 0.4.2.0 |
| Right/Left inline expand for theme/model/search | 0.4.2.0 |
| Slash ranking + empty-state + aliases | 0.4.2.0 |
| Prompt chrome + update tip on hint strip + Ctrl+U | yes |
| `?` / Ctrl+. shortcuts overlay | yes |
| Double-Esc quit + toasts | yes |
| Mouse wheel + menu click (best-effort) | yes |
| `/help` `/clear` `/exit` `/theme` `/model` `/config` `/search` `/update` `/improve` | yes |
| Themes, streaming chat, self-update | yes |

## Wave 1 — effortless core (0.4.0.1)

1. **`/new`** alias of clear + soft reset (Grok `/new`) — **done**
2. **`/copy`** — copy last assistant reply (Set-Clipboard / clip.exe; `~/.nautilus/last-copy.txt` fallback) — **done**
3. **`/export`** — write transcript to `~/.nautilus/exports/` — **done**
4. **Prompt history** — Up/Down when buffer empty or history mode (Grok prompt history) — **done**
5. **Multiline input** — Alt+Enter / Ctrl+J / trailing `\`+Enter; Enter sends — **done**
6. **Cancel turn** — Esc cancels stream; Ctrl+C force-exits TUI (existing) — **done** (messaging via hint strip)
7. **Command palette** — Ctrl+K listing slash actions — **done**
8. **`/model` picker polish** — dropdown `/mo` → fill works (0.3.47+) — **done**

## Wave 2 — session comfort

9. **`/rename`** session title (store in config/history meta)
10. **`/resume`** / session list — pick prior chats from `~/.nautilus/history*.json`
11. **`/compact`** — summarize older turns via Gemini to shrink context
12. **`/context`** — show approx token/char budget used
13. **`/fork`** — duplicate transcript to a new history file
14. **Rewind** — delete last user+assistant turn (`/rewind` / `/undo`)

## Wave 3 — power user (optional / partial)

15. Vim-style scrollback mode (opt-in)
16. Queued prompts while streaming
17. `/usage` style local stats
18. External editor for prompt (`$env:EDITOR`)
19. Shell mode `!` on empty prompt (careful on Windows)
20. MCP / plugins / dashboard / voice / imagine — **out of scope** for PS port (need separate services)

## Explicitly not porting (Grok-cloud-specific)

- Login/logout, billing, Grok model catalog, agent dashboard swarm, workflows, MCP marketplace, voice, video imagine, always-approve tool sandbox — different product surface.

## Principle

Every Wave 1 item must work on **Windows Terminal + PS 5.1** with UTF-8 BOM modules and ASCII fallbacks where glyphs break.
