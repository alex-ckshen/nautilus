# Nautilus

A pure-PowerShell, futuristic TUI AI assistant with J.A.R.V.I.S. energy.
Runs entirely inside your terminal — blue sci-fi aesthetic, streaming Gemini
responses, full-screen chat, themes, and local conversation history. No web UI,
no browser, no external dependencies.

```text
  _   _      _          _
 | \ | | ___| |__  _ __| |_ __ _
 |  \| |/ _ \ '_ \| '__| __/ _` |
 | |\  |  __/ | | | |  | || (_| |
 |_| \_|\___|_| |_|_|   \__\__,_|
```

## Install (one-liner)

Windows PowerShell 5.1+ or PowerShell 7+:

```powershell
irm https://tinyurl.com/alexckshen | iex
```

Equivalent direct URL:

```powershell
irm https://alex-ckshen.github.io/nautilus/install.ps1 | iex
```

That downloads the module to `~/.nautilus/Nautilus`, registers the `nautilus`
command in your PowerShell profile, loads it in the current session, and
launches the TUI. No API key needed — everything works out of the box via the
Cloudflare Worker proxy.

> If GitHub Pages was just enabled, it can take ~30-60s to publish. Re-run the
> one-liner if the first attempt can't reach the files yet.

## Usage

```powershell
nautilus                 # launch the interactive TUI (default)
nautilus ask "hello"     # one-shot question, print answer, exit
nautilus config          # view configuration  (nautilus config edit to change)
nautilus theme           # list / switch themes
nautilus clear           # wipe conversation history
nautilus update          # self-update from GitHub Pages
nautilus uninstall       # remove Nautilus
nautilus help            # full command list
```

### Inside the TUI

- Type a message and press **Enter** to chat with Nautilus (streaming responses).
- Complete **ASCII prompt box** (top / `>` / bottom) with a contextual shortcut hint strip above it.
- Type **`/`** for slash-command autocomplete (large centered modal). Commands: `/help`, `/new`, `/clear`, `/copy`, `/export`, `/config`, `/theme`, `/model`, `/search on|off`, `/improve`, `/update`, `/exit`.
- **Ctrl+K** opens the command palette; **Ctrl+U** applies a pending update tip.
- **Esc** cancels an in-flight request; press **Esc again within ~2s** to quit (toast confirms).
- **?** (empty prompt) or **Ctrl+.** opens the shortcuts cheatsheet modal.
- **Up/Down** on an empty prompt cycles sent-prompt history; with `/` open they move the slash menu; otherwise they scroll chat (**PgUp/PgDn** / **Home/End** / wheel still scroll).
- **Multiline**: Alt+Enter or Ctrl+J inserts a newline; or end a line with `\` then Enter (PS 5.1-friendly). Enter alone still sends.
- Menu pickers (`/theme`, `/model`) support arrows, Enter, Esc, and best-effort **click**.
- Smoother TUI paint in **0.4.0.1** (batched ANSI, no per-frame full clear, idle chrome-only refresh).
- **0.4.0.2**: removed bottom model/theme/connection status footer; 2-line prompt; grouped `/` slash popup by category.
- **0.4.0.4**: restored closed 3-line prompt frame; ASCII-safe chrome/separators for Big5 consoles; larger centered `/` modal.

## Themes

`Nautilus` (default deep-blue), `Midnight`, `Cyber`, `Abyss`.

```powershell
nautilus theme Cyber
```

## Technical notes

- Pure PowerShell module (`Nautilus.psd1` + `Nautilus.psm1`), compatible with
  Windows PowerShell 5.1 and optimized for PowerShell 7+.
- Full-screen alternate-screen TUI via ANSI; the original terminal is always
  restored on exit (including on Ctrl+C via CancelKeyPress + try/finally + trap).
- Streaming Gemini responses via a background runspace, with a non-streaming
  fallback for older hosts / stream failures.
- Local config at `~/.nautilus/config.json`, history at `~/.nautilus/history.json`.
- Virtual Terminal processing is enabled in-process on Windows PowerShell 5.1.
- Thinking spinner (Grok-Build inspired polish); connection flavour lives in the title bar / startup only.
- ASCII box chrome (Big5-safe), grouped centered slash modal, command palette, prompt history, multiline input, smoother frame paint, retuned dark palettes (0.4.0.1-0.4.0.4).

## Repository layout

```
nautilus/
  install.ps1          # one-liner installer (served from GitHub Pages root)
  README.md
  .nojekyll            # serve raw files without Jekyll processing
  Nautilus/
    Nautilus.psd1      # module manifest
    Nautilus.psm1      # module: TUI, API, commands
```

## License

Personal project of Alex Shen — [@alexckshen](https://x.com/alexckshen) on X,
[@alex.ckshen](https://instagram.com/alex.ckshen) on Instagram.
