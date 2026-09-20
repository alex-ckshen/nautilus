# 0.4.2.2

- **Copy-code shortcut (P0 for Alex on WT):** Windows Terminal steals **Ctrl+Shift+C** for host Copy, so the app never sees it. Primary chords are now **F6** and **Ctrl+Alt+C** (plus **Ctrl+Shift+Y**). Ctrl+Shift+C kept as best-effort. **`/cc` / `/copycode` unchanged** (confirmed working).
- **Crash hardening:** no `[ref]$null` default on `Exit-SlashExpand` (PS 5.1 throws); safe dict key checks (OrderedDictionary has no `ContainsKey`); clipboard/mouse/copycode wrapped so they never kill the host; `Exit-TUI` always leaves alt-screen + disables mouse.
- **Scroll:** mouse-wheel scroll-down now sets `NeedsFullPaint`; VT input enabled on stdin for SGR mouse; bare Esc no longer enters mouse parser (was eating keys); Up on empty prompt scrolls when history is empty.
- **Slash L/R collapse:** Left/Esc restores saved buffer (usually `/`) so full catalog returns (not stuck on `/theme`). Menu shows primary name only (`/exit`, not `/exit|/quit`).

# 0.4.2.1


- **Slash L/R collapse:** Left/Esc from an expanded submenu restores the prior buffer (usually `/`) and force-clears so the **full** command list shows again (was stuck filtered to `/theme` etc.).
- **Aliases in the menu:** show primary name only (`/exit`, not `/exit|/quit`). Aliases still match when typing.

# 0.4.2.0

## Copy code fences
- **`/copycode`** (`/cc`) + **Ctrl+Shift+C** (Ctrl+Alt+C fallback): copy markdown fenced code from recent assistant replies.
- One fence → copy immediately; multiple → Select-Menu picker (`1  powershell  Get-Process...`).
- Shared **`Copy-TextToClipboard`** (Set-Clipboard → clip.exe → `~/.nautilus/last-copy.txt`); `/copy` still copies the whole last reply.
- Soft idle hint `Ctrl+Shift+C copy code` when recent replies contain fences.
- SystemPrompt teaches the model to emit language-tagged fences (one clear fence per snippet; prose outside).

## Slash UX polish (friction removed)
- Action-oriented catalog descriptions; aliases (`cc`, `quit`, `keys`) without duplicate rows.
- Filter ranking: **exact → prefix → substring → description** (typing `code` finds `copycode`).
- Empty filter state: centered “no commands match /xyz” instead of a silent blank.
- Wider `/` modal; aliases shown as `/copycode|/cc`; expandable rows show `>`.
- Footer clarifies **tab fill / enter run / right expand / esc dismiss**.
- **Right arrow** drills into **theme / model / search** options inline (Grok-style); **Left** / Esc collapses one level; Enter on a leaf applies.
- Ctrl+K on theme/model/search opens the same inline expand (no second centered Select-Menu hop).
- Unified **`Invoke-SlashCommand`** for Enter + palette (no dual-switch drift).
- Soft confirm only for destructive **`/new`** / **`/clear`** when history is non-empty (default Cancel).
- Bare `/search` expands on|off; `/search on|off` still works.

Proxy / gist / Gemini wiring untouched. UTF-8 BOM on `.psm1`/`.psd1`; `install.ps1` unchanged.

# 0.4.1.3

- **Fix self-update breaking `nautilus` / `naut`** on Windows PowerShell 5.1: `Run-Update` no longer `Import-Module -Force`s itself in-process (that left exported `nautilus` alive while private `Run-TUI` vanished → `CommandNotFoundException: Run-TUI`).
- Update downloads to a temp dir, **parses** `Nautilus.psm1` and checks for `Run-TUI` before replacing install files; then asks you to **open a new PowerShell** window.
- `nautilus` entry soft-heals: if `Run-TUI` is missing, one reload attempt + clear recovery message.

# 0.4.1.2

Versioning note: 0.4.1.x is the UI-polish train (0.4.0.3 → .1, 0.4.0.4 → .2 conceptually). Further feature work stays on later 0.4.1.__ / 0.4.2.__ as needed.

- Restored title status **dot** `◉` (U+25C9) next to `connected` — the 0.4.0.3 ASCII `*` swap was unnecessary on Alex’s host.
- Keeps rounded borders + scrollbar gutter from 0.4.0.4 / 0.4.1.1.

# 0.4.0.4

- **Rounded borders back on** by default (`UseRoundedBorders = $true` → `╭─╮│╰─╯`). ASCII `+ - |` remains the fallback when rounded is off.
- **Scrollbar gutter**: draw width is `WindowWidth - 1` so the Windows console / PowerShell host vertical scrollbar no longer covers the right border (that was the real “missing right edge,” not the rounded glyphs).
- Centered `/` modal and closed 3-line prompt box unchanged from 0.4.0.3.

# 0.4.0.3

## Prompt frame
- Restored a **complete 3-line prompt box** (top + `>` mid + bottom borders) after 0.4.0.2 dropped `promptBot` with the status strip. No model/theme caption inside - just a closed blank with `>` .
- Layout: hint strip above the box; chat ends one row earlier than 0.4.0.2 so all four sides fit.

## ASCII-safe glyphs (zh-TW / Big5 PS 5.1)
- Default chrome is now **ASCII** (`+ - |`) via `UseRoundedBorders = $false` (rounded U+25xx kept as optional fallback). Avoids `?` / clipped edges when box-drawing is double-width or unmapped.
- Role separator `U+203A` (`›`) → `>` (fixes white `?` between Daddy/Nautilus and message).
- Title connected glyph `U+25C9` (`◉`) → `*` .
- Comment separators cleaned to ASCII (`-`, `/`); spinner already ASCII.

## Slash `/` popup
- Larger **centered modal** (not prompt-anchored): roughly middle of the terminal, wider so descriptions fit (or ellipsize cleanly), taller for category headers + more rows.
- Complete four-side box; footer hint `up/down  tab fill  enter run  esc` stays inside with a proper bottom border.
- Groups, type-to-filter, Up/Down/Tab/Enter/Esc, accent selection, mouse/wheel unchanged.

Proxy / gist / Gemini wiring untouched. UTF-8 BOM on `.psm1`/`.psd1`; `install.ps1` unchanged.

# 0.4.0.2

## Chrome
- **Removed bottom status/footer strip** under the `>` prompt (`model · theme · connected to … ---`). Dropped caption painting in `Render-Frame` / `Render-ChromeOnly` and stopped idle `$script:StatusIdx` flavour rotation.
- Prompt chrome is now a **compact 2-line** rounded box (top rule + `>` line), reclaiming one chat row.
- Multiline tip and pending **Update:** tip surface on the existing hint strip only (no new bar).

## Slash `/` popup
- Commands grouped by category for scanning: **Session**, **Clipboard & export**, **Theme & UI**, **Help**.
- Category headers are muted; selected command row stays accent+bold; unselected muted. Filter + Up/Down/Tab/Enter/Esc unchanged.
- Added `/shortcuts` (opens the same cheatsheet as `?` / Ctrl+.). Ctrl+K palette labels include category.

Proxy / gist / Gemini wiring untouched. UTF-8 BOM on `.psm1`/`.psd1`; `install.ps1` unchanged.

# 0.4.0.1

## Smooth rendering
- No full clear (`2J`) every frame - only on Enter-TUI and window resize.
- Each frame batched into one `StringBuilder` + single `[Console]::Out.Write`, wrapped in synchronized update `ESC[?2026h` … `ESC[?2026l`.
- Idle status rotation (~1 Hz) uses `Render-ChromeOnly` (hint + prompt chrome) when chat/buffer unchanged; `$script:NeedsFullPaint` / resize dirty flags force full paint.
- Cursor stays hidden for the whole TUI session.

## Wave 1
- `/new` - clear history + notice (slash catalog + help).
- `/copy` - last assistant reply via `Set-Clipboard` / `clip.exe`, else `~/.nautilus/last-copy.txt`.
- `/export [path]` - markdown transcript under `~/.nautilus/exports/` (timestamp default).
- Prompt history - last ~50 user sends; Up/Down when buffer empty or in history mode (slash menu still owns arrows).
- Multiline - Alt+Enter / Ctrl+J insert newline; trailing `\` then Enter continues line; prompt shows `[...]` + multiline caption.
- Ctrl+K command palette - Select-Menu over slash catalog (fill argful / run the rest). Ctrl+U update unchanged.

## Palette dial
- Semantic roles: `text` / `muted` / `faint` / `accent` / `border` / `good` / `warn` / `error` / `user` / `assistant`.
- Accent reserved for selection, focus, and `>` prompt; chat body uses `text`; soft gray borders; brighter readable body vs faint captions.
- Retuned **Nautilus** + **Midnight** (primary); light pass on Cyber / Abyss.
- Selected slash/menu rows: accent + bold; unselected: muted.

Proxy / gist / Gemini wiring untouched. UTF-8 BOM on `.psm1`/`.psd1`; `install.ps1` remains no-BOM ASCII.

# 0.3.47.0

- **Slash-command autocomplete** (Grok Build completion_dropdown feel): typing `/` in the TUI prompt opens a floating rounded dropdown above the prompt with matching commands (label + short description). Filters as you type; max 6 visible rows with scroll around selection.
- **Keys**: Up/Down move highlight (do not scroll chat); Tab fills `/{name}` (trailing space for argful: theme, model, search, improve); Enter accepts and runs; Esc dismisses the menu and keeps the buffer (double-Esc quit unchanged once menu is closed).
- **Mouse** (best-effort): wheel scrolls the slash menu; click selects a row and runs it.
- `/help`, hint strip, and shortcuts cheatsheet mention `/` opens commands. Spinner ASCII unchanged. Proxy / gist / Gemini wiring untouched. UTF-8 BOM preserved.

# 0.3.46.2 (installer)

- **Root cause:** Windows PS 5.1 `irm` mis-decodes UTF-8 BOM as `ï»¿`, which desyncs the parser and makes later `' | '` / nested quotes look like pipelines.
- **Fix:** `install.ps1` is now **UTF-8 without BOM**, pure ASCII; no `|` inside string literals; prefer `iex (irm ...)` in the header comment.

# 0.3.46.1 (installer)

- **Fix `irm | iex` on Windows PS 5.1**: installer logo no longer uses ASCII-art `|` / nested quotes (those were parsed as empty pipeline elements). Banner is plain text; success lines also drop decorative pipes.

# 0.3.46.0

- **Rounded chrome** (Grok Build prompt_widget): script `Box` glyphs `U+256D/256E/2570/256F` + `U+2500/2502`, `BoxAscii` fallback `+ - |`. `UseRoundedBorders` defaults **true**. `Select-Menu` uses rounded box; `Render-Frame` input is a compact **3-line rounded prompt** (top rule, middle `> ` line, bottom caption with model/theme or update tip).
- **Contextual shortcut hints**: idle strip `enter send / commands ? keys esc quit`; streaming `esc cancel`. **Double-Esc quit** - first Esc arms toast `press esc again to quit` (~2s); second Esc quits. Small toast painted by `Render-Frame`.
- **Shortcuts cheatsheet**: `?` (empty prompt) or **Ctrl+.** opens centered rounded modal of keybindings (aligned with `/help`); Esc / `?` / Ctrl+. closes.
- **Mouse best-effort**: `Enter-TUI` enables VT mouse `?1000h` / `?1006h` (disabled on exit / Ctrl+C). SGR parse for wheel scroll (chat + menus) and menu row click. Chat click left as clear region stub - full hit-testing is fragile on PS 5.1 / some hosts; see note below.
- Spinner remains ASCII `| / - \`. UTF-8 BOM preserved. Proxy / gist / Gemini endpoints unchanged.

### Mouse limits (PS 5.1)
- Relies on terminal VT mouse reporting; conhost/Windows Terminal usually work, ISE does not.
- `[Console]::ReadKey` + ESC-drain SGR parse is best-effort - rapid motion / drag not handled.
- No clipboard selection or click-to-focus in chat yet (stub only).

# 0.3.45.0

- **In-TUI update tip** (Grok Build-inspired): best-effort background check of remote `Nautilus.psd1` `ModuleVersion` vs local; when newer, show centered status tip `Update: vX available, press ctrl+u to restart` (“Update:” bold/accent).
- **Ctrl+U** applies pending update (priority over any line-edit use): leave alt-screen → `Run-Update` → print “Updated to vX - run nautilus again”. Optional `/update` slash command uses the same path.
- **Select-Menu** polish: centered floating ASCII box (`+--+` / `|`), title row, `>` highlight, footer `up/down  enter  esc`; absolute-coord redraw; ASCII `...` only.
- Cleaner input prompt (`> ` ASCII-safe). Spinner remains ASCII `| / - \`. UTF-8 BOM preserved for PS 5.1.

# 0.3.44.1

- **Critical:** ship PowerShell files as **UTF-8 with BOM** so Windows PowerShell 5.1 (e.g. zh-TW CP950) can parse the module. Without BOM, spinner glyphs corrupted and `Import-Module` failed - `nautilus` not found after install.
- Replace braille spinner with ASCII `| / - \`.
- Installer: do not call `nautilus` unless import succeeded; print real import errors.

# Nautilus 0.3.44.0 - polish changelog

Built on 0.3.43.1. Proxy, gist key URL, and Gemini endpoint wiring are unchanged.

## Version
- **0.3.44.0** in both `Nautilus.psm1` (`$script:NautilusVersion`) and `Nautilus.psd1` (`ModuleVersion`)

## Load-failure hardening
- **`Test-NautilusHost`**: checks real console, window size (≥40×12), `KeyAvailable`, host name (ISE / ServerRemoteHost), PS version; called at the start of `Run-TUI` with actionable messages (suggest Terminal/conhost or `nautilus ask`)
- **`Enable-VT` / Add-Type**: reuses `[Nautilus.NautilusCon]` if already loaded; never throws on Constrained Language / non-console / re-import; validates console handle before `SetConsoleMode`
- **`Set-Alias naut`**: wrapped in try/catch (Global → Local fallback) so module import still succeeds
- **Import-time dirs**: create `~/.nautilus` safely (no throw during import)
- **`Enter-TUI` / main-loop `ReadKey`**: try/catch so missing console fails with a clear exit instead of a raw exception
- **Installer**: fixed invalid regex `'[/\]'` (could throw *Invalid pattern*) - path detection now uses `IndexOf`; PS 5.1-safe Windows check (no bare `$IsWindows`)

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
- Import in Windows PowerShell 5.1 and pwsh 7+ (twice in same process - Add-Type re-import)
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
