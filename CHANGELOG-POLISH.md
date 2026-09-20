# 0.3.46.0

- **Rounded chrome** (Grok Build prompt_widget): script `Box` glyphs `U+256D/256E/2570/256F` + `U+2500/2502`, `BoxAscii` fallback `+ - |`. `UseRoundedBorders` defaults **true**. `Select-Menu` uses rounded box; `Render-Frame` input is a compact **3-line rounded prompt** (top rule, middle `> ` line, bottom caption with model/theme or update tip).
- **Contextual shortcut hints**: idle strip `enter send / commands ? keys esc quit`; streaming `esc cancel`. **Double-Esc quit** — first Esc arms toast `press esc again to quit` (~2s); second Esc quits. Small toast painted by `Render-Frame`.
- **Shortcuts cheatsheet**: `?` (empty prompt) or **Ctrl+.** opens centered rounded modal of keybindings (aligned with `/help`); Esc / `?` / Ctrl+. closes.
- **Mouse best-effort**: `Enter-TUI` enables VT mouse `?1000h` / `?1006h` (disabled on exit / Ctrl+C). SGR parse for wheel scroll (chat + menus) and menu row click. Chat click left as clear region stub — full hit-testing is fragile on PS 5.1 / some hosts; see note below.
- Spinner remains ASCII `| / - \`. UTF-8 BOM preserved. Proxy / gist / Gemini endpoints unchanged.

### Mouse limits (PS 5.1)
- Relies on terminal VT mouse reporting; conhost/Windows Terminal usually work, ISE does not.
- `[Console]::ReadKey` + ESC-drain SGR parse is best-effort — rapid motion / drag not handled.
- No clipboard selection or click-to-focus in chat yet (stub only).

# 0.3.45.0

- **In-TUI update tip** (Grok Build–inspired): best-effort background check of remote `Nautilus.psd1` `ModuleVersion` vs local; when newer, show centered status tip `Update: vX available, press ctrl+u to restart` (“Update:” bold/accent).
- **Ctrl+U** applies pending update (priority over any line-edit use): leave alt-screen → `Run-Update` → print “Updated to vX — run nautilus again”. Optional `/update` slash command uses the same path.
- **Select-Menu** polish: centered floating ASCII box (`+--+` / `|`), title row, `>` highlight, footer `up/down  enter  esc`; absolute-coord redraw; ASCII `...` only.
- Cleaner input prompt (`> ` ASCII-safe). Spinner remains ASCII `| / - \`. UTF-8 BOM preserved for PS 5.1.

# 0.3.44.1

- **Critical:** ship PowerShell files as **UTF-8 with BOM** so Windows PowerShell 5.1 (e.g. zh-TW CP950) can parse the module. Without BOM, spinner glyphs corrupted and `Import-Module` failed — `nautilus` not found after install.
- Replace braille spinner with ASCII `| / - \`.
- Installer: do not call `nautilus` unless import succeeded; print real import errors.

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
