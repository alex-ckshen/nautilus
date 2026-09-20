# Nautilus vs Grok Build — feature map (Path A: PowerShell)

Source: xai-org/grok-build docs (`user-guide/03-keyboard-shortcuts.md`, `04-slash-commands.md`) + pager actions/slash registry.
Nautilus stays pure PowerShell; we port *behaviour*, not Rust crates.

## Already in Nautilus (or landing in 0.3.47)

| Area | Status |
|------|--------|
| `/` slash menu with type-to-filter dropdown | 0.3.47 |
| Rounded prompt chrome, update tip + Ctrl+U | yes |
| `?` / Ctrl+. shortcuts overlay | yes |
| Double-Esc quit + toasts | yes |
| Mouse wheel + menu click (best-effort) | yes |
| `/help` `/clear` `/exit` `/theme` `/model` `/config` `/search` `/update` `/improve` | yes |
| Themes, streaming chat, self-update | yes |

## Wave 1 — effortless core (next)

Port these first; highest daily-use payoff, feasible in PS TUI:

1. **`/new`** alias of clear + soft reset (Grok `/new`)
2. **`/copy`** — copy last assistant reply (clip.exe / pbcopy / xclip; file fallback)
3. **`/export`** — write transcript to `~/.nautilus/exports/`
4. **Prompt history** — Up/Down when buffer empty or history mode (Grok prompt history)
5. **Multiline input** — Shift+Enter or `/multiline` toggle; Enter sends
6. **Cancel turn** — Ctrl+C clearly cancels stream (already Esc; align messaging)
7. **Command palette** — Ctrl+K or Ctrl+P listing actions (subset of Grok palette)
8. **`/model` picker polish** — already exists; ensure dropdown `/mo` → fill works

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
