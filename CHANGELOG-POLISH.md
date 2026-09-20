# Nautilus 0.3.43.0 — polish changelog

Shipped from live code (`nautilus-ref` / Pages mirror). Proxy / API key / gist wiring unchanged.

## Version
- Module + manifest aligned to **0.3.43.0** (`Nautilus.psm1` `$script:NautilusVersion`, `Nautilus.psd1` `ModuleVersion`)

## Concrete bugs fixed

### Alternate screen / exit
- Alt-screen not restored on Ctrl+C — added `Register-TuiCancelHandler` / `Unregister-TuiCancelHandler` (`CancelKeyPress`, `$e.Cancel = $true`) plus `trap` + outer `try/finally` calling `Exit-TUI`
- `Exit-TUI` hardened: leave alt screen (`?1049l`), show cursor (`?25h`), reset SGR; gated by `$script:TuiActive`
- In-flight stream cancelled on Esc / force-exit; `Dispose-StreamState` always run in `finally`

### Frame / render / rows
- Chat viewport overlapped top border (`$chatTop = 2` while border painted on row 2) — now `$chatTop = 3` with explicit layout: title(1) / border(2) / chat(3..h-3) / border(h-2) / status(h-1) / input(h)
- Ghost characters after shorter redraws — `Write-At -ClearEol` + leftover chat rows cleared
- Empty history slice / null messages — guarded; home screen uses `@($messages).Count`
- Message body always painted in accent colour — `Themed` was called with numeric colour codes (fell through to `default`); now uses role names (`'user'` / `'assistant'` / `'system'`)
- Hardcoded `prefixLen = 8` wrong for "Daddy" vs "Nautilus" — now `VisibleLen` of the real prefix

### Scroll / wrap
- Pin-to-bottom sentinel (`[int]::MaxValue`) vs clamp clarified; empty viewport no longer indexes an empty list with `..`
- `Wrap-Text` overflowed on tokens longer than width (URLs/paths) — hard-splits oversize words; skips empty residual after split
- Home / End jump scroll to top / bottom (chat history)

### Streaming / dispose / races
- `StringBuilder.Full` Append (runspace) vs `ToString` (UI) race — `Monitor.Enter/Exit` around Append; UI reads via `Get-StreamFullText`
- Stream `HttpWebRequest` reader/response not closed on error path — `finally` always closes `$reader` / `$resp`
- Double-dispose / hang on cancel — `Dispose-StreamState` is idempotent (`_Disposed`), stops incomplete pipeline before `EndInvoke`
- `nautilus ask` and improve/chat paths dispose in `finally`; Esc cancels in-flight TUI streams

### Input / UX polish
- Thinking spinner + rotating short status lines on the status bar while streaming; idle flavour status rotates
- Crisp accent prompt (`▶`); input line always EOL-cleared
- Cleaner header (version + connected + model) without full `2J` flicker every frame

### Installer / update / uninstall (PS 5.1 + 7)
- `nautilus update` used 3-arg `Join-Path` (PS 7 only) — rewritten to nested 2-arg `Join-Path` for Windows PowerShell 5.1
- Installer logo backticks eaten in double-quoted strings — logo lines are single-quoted
- Installer profile target fallback safer when `$PROFILE.*` missing; download URLs remain `$RepoBase/Nautilus/{psd1,psm1}`
- Empty history `ConvertTo-Json` on PS 5.1 could emit nothing — `ConvertTo-Json -InputObject @($messages)` with `[]` fallback
- Default theme aligned to **Nautilus** (was Midnight in config defaults)

## Commands preserved
Shell: `nautilus`, `ask`, `config`, `theme`, `clear`, `update`, `uninstall`, `help`  
In-TUI: `/help`, `/clear`, `/config`, `/theme`, `/model`, `/search`, `/improve`, `/exit` (+ Esc)

## Unchanged (by design)
- Cloudflare Worker proxy URL and gist key fetch wiring — not modified unless broken (they were not)

## Syntax sanity
- Brace balance on `Nautilus.psm1` and `install.ps1`: depth 0, no unmatched braces (static scan)

## Windows still to verify (on GitHub Desktop clone / real console)
- VT / alt-screen restore on Windows Terminal, conhost, and Windows PowerShell 5.1 specifically
- Ctrl+C restore while streaming and while idle
- Arrow / PgUp / PgDn scroll feel; resize mid-chat
- `nautilus update` / `uninstall` / re-install one-liner against live Pages
- Gemini stream via Worker + non-stream fallback
- One-liner: `irm https://tinyurl.com/alexckshen | iex` and direct Pages `install.ps1`

## Install / Pages paths
- `RepoBase` = `https://alex-ckshen.github.io/nautilus`
- Module files: `https://alex-ckshen.github.io/nautilus/Nautilus/Nautilus.psd1` (+ `.psm1`)
- Installer: `https://alex-ckshen.github.io/nautilus/install.ps1`
