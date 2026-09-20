# Nautilus 0.3.44.0 — polish changelog

Built on 0.3.43.1. Proxy, gist key URL, and Gemini endpoint wiring are unchanged.

## Version
- **0.3.44.0** in both `Nautilus.psm1` (`$script:NautilusVersion`) and `Nautilus.psd1` (`ModuleVersion`)

## Load-failure hardening
- **`Test-NautilusHost`**: checks real console, window size (≥40×12), `KeyAvailable`, host name (ISE / ServerRemoteHost), PS version; called at the start of `Run-TUI` with actionable messages (suggest Terminal/conhost or `nautilus ask`)
- **`Enable-VT` / Add-Type**: reuses `[Nautilus.NautilusCon]` if already loaded; never throws on Constrained Language / non-console / re-import; validates console handle before `SetConsoleMode`
- **`Set-Alias naut`**: wrapped in try/catch (Global → Local fallback) so module import still succeeds
- **Import-time dirs**: create `~/.nautilus` safely (no throw during import)
- **`Enter-TUI` / main-loop `ReadKey`**: try/catch so missing console fails with a clear exit instead of a raw exception
- **Installer**: fixed invalid regex `'[/\]'` (could throw *Invalid pattern*) — path detection now uses `IndexOf`; PS 5.1-safe Windows check (no bare `$IsWindows`)

## Update hardening (`nautilus update`)
- Nested 2-arg `Join-Path` (PS 5.1)
- Creates module dirs; Unblock-File when available
- Download order: native **curl.exe/curl** → **HttpClient** → **Invoke-WebRequest** (Windows only)
- Path vs name detection without fragile regex
- Reloads module after download and prints **new version** (`v0.3.44.0`); clear failure / “restart session” messages

## Dropdown menus (`Select-Menu`)
- Empty / null options → return `$null` (no crash)
- Arrow Up/Down wrap; Home/End; Enter select; Esc cancel
- Clamps box to window; scrolls long lists; truncates long labels
- Absolute-coord redraw (no stacking); restores prior `CursorVisible` (keeps TUI cursor hidden)
- Safe `WindowWidth`/`Height`/`ReadKey` when console is flaky

## Search default
- `enableSearch = $false` unchanged (fresh installs avoid Google Search grounding 429s)

## Commands preserved
Shell: `nautilus`, `ask`, `config`, `theme`, `clear`, `update`, `uninstall`, `help`  
In-TUI: `/help`, `/clear`, `/config`, `/theme`, `/model`, `/search`, `/improve`, `/exit` (+ Esc)

## Unchanged (by design)
- Cloudflare Worker proxy URL
- Gist API-key URL
- Direct Gemini API endpoint

## Windows retest checklist
- Import in Windows PowerShell 5.1 and pwsh 7+ (twice in same process — Add-Type re-import)
- Launch in Windows Terminal + conhost; confirm ISE prints host warning instead of crashing
- `/theme` and `/model` dropdowns: arrows, Enter, Esc, small window
- `nautilus update` against live Pages; version banner shows 0.3.44.0
- Ctrl+C / Esc alt-screen restore; slash commands + status line
- One-liner: `irm https://tinyurl.com/alexckshen | iex`

## Pages paths
- `RepoBase` = `https://alex-ckshen.github.io/nautilus`
- Module: `.../nautilus/Nautilus/Nautilus.psd1` (+ `.psm1`)
- Installer: `.../nautilus/install.ps1`
- One-liner: `irm https://tinyurl.com/alexckshen | iex`
