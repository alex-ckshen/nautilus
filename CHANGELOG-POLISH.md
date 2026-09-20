# Nautilus 0.3.43.0 polish

## Fixes
- Alternate-screen restore on normal exit **and** Ctrl+C (`Register-TuiCancelHandler` + `try/finally` + `trap`)
- Hardened `Exit-TUI` (leave alt screen, show cursor, reset SGR; idempotent via `$script:TuiActive`)
- `Render-Frame` layout clarified (title / border / chat / status / input rows) with EOL clears to reduce flicker/ghosting
- Idle status line rotates short flavour messages (Grok-Build-style “alive” feel)
- `Write-At -ClearEol` and `Clear-Row` helpers for cleaner redraws
- Stream dispose paths reviewed; force-exit flag aborts main loop safely

## Unchanged (by design)
- Cloudflare Worker / Gemini API proxy wiring and key fetch — not modified

## Verify on Windows (GitHub Desktop clone → install)
```powershell
irm https://alex-ckshen.github.io/nautilus/install.ps1 | iex
nautilus
```
Then: chat, scroll, Esc exit, Ctrl+C restore, `/theme`, `/help`, `/clear`, resize window.
