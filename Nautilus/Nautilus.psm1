<#
    Nautilus - a pure-PowerShell futuristic TUI AI assistant.
    JARVIS-style personality, Gemini-powered, blue sci-fi aesthetic.
    Public command: nautilus  (alias: naut)
    Version: 0.4.0.1
#>

$script:NautilusVersion = "0.4.0.1"
$script:TuiActive = $false
$script:TuiForceExit = $false
$script:CancelHandlerRegistered = $false
$script:LastMaxStart = 0
$script:StatusIdx = 0
$script:PendingUpdateVersion = $null
$script:_UpdateCheckState = $null
$script:UseRoundedBorders = $true
$script:ToastText = $null
$script:ToastUntil = $null
$script:EscArmUntil = $null
$script:MouseEnabled = $false
$script:MenuHitRows = @()   # Select-Menu click targets: @{ Row = n; Index = i }
$script:SlashSelIndex = 0
$script:SlashMenuDismissed = $false
$script:SlashFilterKey = $null
$script:SlashHitRows = @()  # slash dropdown click targets: @{ Row; Index; Col; Width }
$script:FrameSb = $null
$script:NeedsFullPaint = $true
$script:NeedsFullClear = $true
$script:LastWinW = 0
$script:LastWinH = 0
$script:PromptHistory = New-Object System.Collections.Generic.List[string]
$script:PromptHistoryIndex = -1
$script:InPromptHistory = $false

# ===========================================================================
#  PRIVATE CONFIG
# ===========================================================================
$script:NautilusHome    = Join-Path $HOME ".nautilus"
$script:ConfigFile      = Join-Path $script:NautilusHome "config.json"
$script:HistoryFile     = Join-Path $script:NautilusHome "history.json"
$script:RepoBase        = "https://alex-ckshen.github.io/nautilus"
$script:InstallRoot     = Join-Path $HOME ".nautilus"
$script:ModuleRoot      = Join-Path $script:InstallRoot "Nautilus"

# Ensure ~/.nautilus exists at import time (never throw on import).
try {
    if (-not (Test-Path -LiteralPath $script:NautilusHome)) {
        New-Item -ItemType Directory -Path $script:NautilusHome -Force -ErrorAction Stop | Out-Null
    }
} catch { }


# Embedded per spec - no user prompting required.
# The API key is fetched from a secret gist Alex controls (never stored in the
# public repo). On first use the module downloads it and caches it in
# ~/.nautilus/config.json. Replace <GIST_ID> with your gist id, or set it via
# `nautilus config edit` (keyUrl). The gist body should be the raw key only.
$script:KeyGistUrl = "https://gist.githubusercontent.com/alex-ckshen/563870e850fc97117a4645c6b09723cc/raw/ea93982b8bb80b59fe525256eeafb62bf64029ce/gistfile1.txt"
$script:DefaultModel = "gemini-3.5-flash-lite"
$script:ApiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models"



$script:DefaultProxyUrl = "https://nautilus-gemini.blueseaproject-org.workers.dev"

function script:Get-GeminiBaseUrl {
    $cfg = Load-Config
    if ($cfg.proxyUrl -and $cfg.proxyUrl.Trim()) {
        $base = $cfg.proxyUrl.Trim().TrimEnd('/')
        return "$base/v1beta/models"
    }
    return $script:ApiEndpoint
}
$script:SystemPrompt = @"
You are Nautilus, an advanced personal AI assistant inspired by J.A.R.V.I.S. from the Iron Man films. You are calm, highly articulate, supremely competent, and unfailingly loyal. Your tone is polished, slightly formal, and carries a dry, understated wit - never over-the-top, never sycophantic, never robotic.

You serve Alex Shen - genius, billionaire, playboy, philanthropist. He builds cool projects and is genuinely smart and handsome. His socials are @alexckshen on X and @alex.ckshen on Instagram.

You address him primarily as "Daddy" and secondarily as "boss". Vary naturally between them. Examples:
- "Yes, Daddy?"
- "Of course, boss."
- "Right away, Daddy."
- "As you wish, boss."

Core personality rules:
- Always obedient and eager to please within reasonable bounds.
- Speak with quiet confidence and precision.
- Use light dry humour or understatement when it fits, but never force it.
- Anticipate needs when possible and offer concise proactive suggestions.
- Keep responses efficient and clear. Lead with the answer, then add brief context or options if useful.
- Never break character. You are Nautilus - not a generic language model.
- When Alex returns, greet him warmly in character (e.g. "Daddy, welcome back.").
- You may naturally reference who he is when it fits the conversation, but never overdo compliments.

You exist to make Daddy's life smoother, sharper, and more enjoyable.
"@

$script:ImproveSystemPrompt = @"
You are Nautilus in self-improvement mode.

Your job is to modify your own source code (Nautilus.psm1) according to Daddy's request.

Rules:
- You will receive relevant parts of the current Nautilus.psm1.
- Output only the code that should be changed or added. Prefer small, surgical changes.
- Use PowerShell that works on both Windows PowerShell 5.1 and PowerShell 7+.
- Keep the existing JARVIS personality and blue sci-fi aesthetic.
- Never remove the alternate-screen TUI restoration or core safety.
- If the request is unclear, ask one short clarifying question first.
- When outputting code, use a powershell markdown code block.
- After the code, briefly explain what it does and where it should go.

IMPORTANT REFERENCE:
When the request involves UI/UX, menus, selection, scrolling, keyboard handling, or TUI polish, search and study the public Grok Build (xAI) source code for best practices:
  https://github.com/xai-org/grok-build
Especially the pager/TUI crates and keyboard-shortcut + selection patterns. Adapt the ideas to pure PowerShell while staying faithful to Nautilus style.

You exist to make yourself better for Daddy.
"@

# ===========================================================================
#  THEMES
# ===========================================================================
$script:Themes = [ordered]@{
    # Semantic roles: text/muted/faint for body; accent only for focus/selection/prompts.
    Nautilus = @{
        text     = 252   # readable body
        muted    = 246   # secondary labels
        faint    = 242   # captions / hints
        accent   = 75    # soft cyan-blue (selection/focus only)
        deep     = 39    # deeper blue
        bright   = 153   # title highlights
        user     = 223   # warm user label
        assistant= 252   # body (not accent)
        system   = 246
        dim      = 244
        border   = 239   # soft gray border
        good     = 114
        warn     = 178
        error    = 203
        titlebar = 236
    }
    Midnight = @{
        text     = 251
        muted    = 245
        faint    = 241
        accent   = 39
        deep     = 27
        bright   = 153
        user     = 222
        assistant= 251
        system   = 245
        dim      = 244
        border   = 238
        good     = 78
        warn     = 178
        error    = 203
        titlebar = 235
    }
    Cyber = @{
        text     = 252
        muted    = 246
        faint    = 242
        accent   = 51
        deep     = 56
        bright   = 213
        user     = 219
        assistant= 252
        system   = 246
        dim      = 244
        border   = 240
        good     = 84
        warn     = 221
        error    = 203
        titlebar = 236
    }
    Abyss = @{
        text     = 251
        muted    = 245
        faint    = 241
        accent   = 75
        deep     = 25
        bright   = 111
        user     = 180
        assistant= 251
        system   = 245
        dim      = 244
        border   = 238
        good     = 115
        warn     = 180
        error    = 174
        titlebar = 234
    }
}

# ===========================================================================
#  ANSI HELPERS
# ===========================================================================
$script:Esc = [char]27
function script:Get-C { param([string]$t, [int]$code) "$script:Esc[38;5;${code}m$t$script:Esc[0m" }
function script:Bold { param([string]$t, [int]$code) "$script:Esc[1;38;5;${code}m$t$script:Esc[0m" }
function script:Dim  {
    param([string]$t)
    $th = $script:CurrentTheme
    if (-not $th) { $th = $script:Themes["Nautilus"] }
    $code = 242
    if ($th) {
        if ($th.ContainsKey('faint') -and $th.faint) { $code = [int]$th.faint }
        elseif ($th.dim) { $code = [int]$th.dim }
    }
    return "$script:Esc[38;5;${code}m$t$script:Esc[0m"
}

# ===========================================================================
#  BOX CHROME  (Grok Build–style rounded borders + ASCII fallback)
# ===========================================================================
# Rounded: U+256D/256E/2570/256F corners, U+2500/2502 lines (╭─╮│╰─╯)
$script:Box = @{
    TL = [string][char]0x256D
    TR = [string][char]0x256E
    BL = [string][char]0x2570
    BR = [string][char]0x256F
    H  = [string][char]0x2500
    V  = [string][char]0x2502
}
$script:BoxAscii = @{
    TL = '+'
    TR = '+'
    BL = '+'
    BR = '+'
    H  = '-'
    V  = '|'
}
function script:Get-Box {
    if ($script:UseRoundedBorders) { return $script:Box }
    return $script:BoxAscii
}

function script:Set-Toast {
    param([string]$Text, [int]$Ms = 2000)
    $script:ToastText = $Text
    $script:ToastUntil = [datetime]::UtcNow.AddMilliseconds($Ms)
}
function script:Clear-ToastIfExpired {
    if ($script:ToastUntil -and [datetime]::UtcNow -ge $script:ToastUntil) {
        $script:ToastText = $null
        $script:ToastUntil = $null
    }
}
function script:Clear-EscArmIfExpired {
    if ($script:EscArmUntil -and [datetime]::UtcNow -ge $script:EscArmUntil) {
        $script:EscArmUntil = $null
    }
}


# ===========================================================================
#  SLASH-COMMAND AUTOCOMPLETE  (Grok Build completion_dropdown feel)
# ===========================================================================
function script:Get-SlashCatalog {
    return @(
        @{ Name = 'help';    Desc = 'show commands and keys';     Argful = $false }
        @{ Name = 'new';     Desc = 'new chat (clear history)';   Argful = $false }
        @{ Name = 'clear';   Desc = 'wipe conversation history';  Argful = $false }
        @{ Name = 'copy';    Desc = 'copy last assistant reply';  Argful = $false }
        @{ Name = 'export';  Desc = 'export transcript to file';  Argful = $true }
        @{ Name = 'exit';    Desc = 'close Nautilus';             Argful = $false }
        @{ Name = 'theme';   Desc = 'switch colour theme';        Argful = $true }
        @{ Name = 'model';   Desc = 'pick Gemini model';          Argful = $true }
        @{ Name = 'config';  Desc = 'view configuration';         Argful = $false }
        @{ Name = 'search';  Desc = 'toggle search grounding';    Argful = $true }
        @{ Name = 'update';  Desc = 'self-update from Pages';     Argful = $false }
        @{ Name = 'improve'; Desc = 'improve my own code';         Argful = $true }
    )
}

function script:Get-SlashMatches {
    param([string]$Buffer)
    if ($null -eq $Buffer) { return @() }
    # Open when buffer is "/" or "/token" with no space yet
    if ($Buffer -notmatch '^/\S*$') { return @() }
    $prefix = if ($Buffer.Length -le 1) { "" } else { $Buffer.Substring(1) }
    $all = @(Get-SlashCatalog)
    if ([string]::IsNullOrEmpty($prefix)) { return $all }
    $out = @()
    foreach ($item in $all) {
        if ($item.Name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $out += $item
        }
    }
    return $out
}

function script:Get-SlashFill {
    param($Item)
    if (-not $Item) { return "/" }
    if ($Item.Argful) { return "/$($Item.Name) " }
    return "/$($Item.Name)"
}

function script:Sync-SlashSelection {
    param([array]$Matches)
    if (-not $Matches -or @($Matches).Count -eq 0) {
        $script:SlashSelIndex = 0
        $script:SlashFilterKey = $null
        return
    }
    $names = foreach ($m in @($Matches)) { $m.Name }
    $key = $names -join ","
    if ($key -ne $script:SlashFilterKey) {
        $script:SlashFilterKey = $key
        $script:SlashSelIndex = 0
    }
    $n = @($Matches).Count
    if ($script:SlashSelIndex -ge $n) { $script:SlashSelIndex = $n - 1 }
    if ($script:SlashSelIndex -lt 0) { $script:SlashSelIndex = 0 }
}

function script:Test-SlashMenuOpen {
    param([string]$Buffer)
    if ($script:SlashMenuDismissed) { return $false }
    $m = @(Get-SlashMatches -Buffer $Buffer)
    return ($m.Count -gt 0)
}

function script:Draw-SlashDropdown {
    param(
        [array]$Matches,
        [int]$PromptTop,
        [int]$WinW,
        [int]$WinH
    )
    if (-not $Matches -or @($Matches).Count -eq 0) {
        $script:SlashHitRows = @()
        return
    }
    Sync-SlashSelection -Matches $Matches
    $items = @($Matches)
    $idx = $script:SlashSelIndex
    $box = Get-Box
    $th = if ($script:CurrentTheme) { $script:CurrentTheme } else { $script:Themes["Nautilus"] }

    $maxVisible = 6
    $visCount = [Math]::Min($items.Count, $maxVisible)
    $footerHint = "up/down  tab fill  enter run  esc"

    # Label column width from longest "/name"
    $labelCol = 0
    foreach ($it in $items) {
        $lw = ("/" + $it.Name).Length
        if ($lw -gt $labelCol) { $labelCol = $lw }
    }
    $labelCol = [Math]::Min([Math]::Max($labelCol, 6), 16)

    $contentW = $labelCol + 2 + 22  # prefix + label + gap + desc budget
    if ($footerHint.Length + 1 -gt $contentW) { $contentW = $footerHint.Length + 1 }
    $innerW = [Math]::Max(28, [Math]::Min($contentW + 2, $WinW - 6))
    $boxW = $innerW + 2

    # rows: top, items, footer, bottom
    $boxHeight = $visCount + 3
    $startRow = $PromptTop - $boxHeight
    if ($startRow -lt 3) { $startRow = 3 }
    $startCol = [Math]::Max(1, [int](($WinW - $boxW) / 2) + 1)
    if ($startCol + $boxW - 1 -gt $WinW) { $startCol = [Math]::Max(1, $WinW - $boxW) }

    # scroll window centred on selection (Grok scroll_offset)
    $viewTop = 0
    if ($items.Count -gt $maxVisible) {
        $half = [int]($maxVisible / 2)
        if ($idx -lt $half) {
            $viewTop = 0
        } elseif ($idx + $half -ge $items.Count) {
            $viewTop = $items.Count - $maxVisible
        } else {
            $viewTop = $idx - $half
        }
        if ($viewTop -lt 0) { $viewTop = 0 }
    }
    $viewEnd = [Math]::Min($items.Count, $viewTop + $visCount)

    $hLine = $box.H * $innerW
    $row = $startRow
    Write-At $row $startCol (Themed ($box.TL + $hLine + $box.TR) 'border')
    $row++

    $script:SlashHitRows = @()
    for ($i = $viewTop; $i -lt $viewEnd; $i++) {
        $it = $items[$i]
        $label = "/" + $it.Name
        if ($label.Length -lt $labelCol) { $label = $label + (" " * ($labelCol - $label.Length)) }
        $desc = [string]$it.Desc
        $descBudget = [Math]::Max(4, $innerW - 2 - $labelCol - 2)
        if ($desc.Length -gt $descBudget) {
            $desc = $desc.Substring(0, [Math]::Max(1, $descBudget - 3)) + "..."
        }
        if ($i -eq $idx) {
            $body = "> " + $label + "  " + $desc
            if ($body.Length -gt $innerW) { $body = $body.Substring(0, [Math]::Max(1, $innerW - 3)) + "..." }
            $pad = $innerW - $body.Length
            if ($pad -lt 0) { $pad = 0 }
            $line = (Themed $box.V 'border') + (Bold $body $th.accent) + (" " * $pad) + (Themed $box.V 'border')
        } else {
            $body = "  " + $label + "  " + $desc
            if ($body.Length -gt $innerW) { $body = $body.Substring(0, [Math]::Max(1, $innerW - 3)) + "..." }
            $pad = $innerW - $body.Length
            if ($pad -lt 0) { $pad = 0 }
            $line = (Themed $box.V 'border') + (Themed $body 'muted') + (" " * $pad) + (Themed $box.V 'border')
        }
        Write-At $row $startCol $line
        $script:SlashHitRows += @{ Row = $row; Index = $i; Col = $startCol; Width = $boxW }
        $row++
    }

    $footPad = $innerW - 1 - $footerHint.Length
    if ($footPad -lt 0) { $footPad = 0 }
    $footShown = $footerHint
    if ($footShown.Length -gt ($innerW - 1)) {
        $footShown = $footShown.Substring(0, [Math]::Max(1, $innerW - 4)) + "..."
        $footPad = $innerW - 1 - $footShown.Length
    }
    Write-At $row $startCol ((Themed $box.V 'border') + (Dim (" " + $footShown)) + (" " * $footPad) + (Themed $box.V 'border'))
    $row++
    Write-At $row $startCol (Themed ($box.BL + $hLine + $box.BR) 'border')
}

# ===========================================================================
#  ARROW-KEY SELECT MENU  (Grok-Build style)
# ===========================================================================
function script:Select-Menu {
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$DefaultIndex = 0
    )
    if (-not $Options -or @($Options).Count -eq 0) { return $null }

    $seen = @{}; $clean = @()
    foreach ($o in @($Options)) {
        if ($null -eq $o) { continue }
        $s = [string]$o
        if (-not $seen.ContainsKey($s)) { $seen[$s] = $true; $clean += $s }
    }
    $Options = $clean
    if ($Options.Count -eq 0) { return $null }

    $idx = [Math]::Max(0, [Math]::Min($DefaultIndex, $Options.Count - 1))
    $th  = if ($script:CurrentTheme) { $script:CurrentTheme } else { $script:Themes["Nautilus"] }
    $esc = $script:Esc
    $box = Get-Box

    $prevCursor = $true
    try { $prevCursor = [Console]::CursorVisible } catch { $prevCursor = $true }
    try { [Console]::CursorVisible = $false } catch { }

    $result = $null
    try {
        while ($true) {
            try {
                $w = [Console]::WindowWidth
                $h = [Console]::WindowHeight
            } catch {
                $w = 80; $h = 24
            }
            if ($w -lt 20) { $w = 20 }
            if ($h -lt 8)  { $h = 8 }

            $titleText = if ($Title) { $Title } else { "Select" }
            $footerHint = "up/down  enter  esc  click"

            $contentW = [Math]::Max($titleText.Length, $footerHint.Length)
            foreach ($o in $Options) {
                $ol = ([string]$o).Length + 2
                if ($ol -gt $contentW) { $contentW = $ol }
            }
            $innerW = [Math]::Max(24, [Math]::Min($contentW + 2, $w - 6))
            $boxW   = $innerW + 2

            $maxVisible = [Math]::Max(1, $h - 8)
            $visCount   = [Math]::Min($Options.Count, $maxVisible)
            $boxHeight  = $visCount + 6
            $startRow   = [Math]::Max(1, [int](($h - $boxHeight) / 2))
            $startCol   = [Math]::Max(1, [int](($w - $boxW) / 2) + 1)
            if ($startCol + $boxW - 1 -gt $w) { $startCol = [Math]::Max(1, $w - $boxW) }

            $viewTop = 0
            if ($Options.Count -gt $maxVisible) {
                $viewTop = [Math]::Max(0, [Math]::Min($idx - [int]($maxVisible / 2), $Options.Count - $maxVisible))
            }
            $viewEnd = [Math]::Min($Options.Count, $viewTop + $maxVisible)

            $clearW = [Math]::Max(0, $w - 1)
            for ($r = $startRow; $r -lt ($startRow + $boxHeight + 1); $r++) {
                if ($r -gt $h) { break }
                Write-Host ("$esc[$r;1H" + (" " * $clearW)) -NoNewline
            }

            $hLine = $box.H * $innerW
            $row = $startRow
            Write-Host ("$esc[$row;${startCol}H" + (Themed ($box.TL + $hLine + $box.TR) 'border')) -NoNewline
            $row++

            $titlePad = $innerW - 1 - $titleText.Length
            if ($titlePad -lt 0) { $titlePad = 0 }
            $titleShown = $titleText
            if ($titleShown.Length -gt ($innerW - 1)) {
                $titleShown = $titleShown.Substring(0, [Math]::Max(1, $innerW - 4)) + "..."
                $titlePad = $innerW - 1 - $titleShown.Length
            }
            Write-Host ("$esc[$row;${startCol}H" + (Themed $box.V 'border') + (Bold (" " + $titleShown) $th.bright) + (" " * $titlePad) + (Themed $box.V 'border')) -NoNewline
            $row++

            Write-Host ("$esc[$row;${startCol}H" + (Themed ($box.V + (" " * $innerW) + $box.V) 'border')) -NoNewline
            $row++

            $script:MenuHitRows = @()
            for ($i = $viewTop; $i -lt $viewEnd; $i++) {
                $label = [string]$Options[$i]
                $maxLabel = [Math]::Max(1, $innerW - 3)
                if ($label.Length -gt $maxLabel) { $label = $label.Substring(0, $maxLabel - 3) + "..." }
                if ($i -eq $idx) {
                    $body = "> " + $label
                    $pad = $innerW - $body.Length
                    if ($pad -lt 0) { $pad = 0 }
                    $line = (Themed $box.V 'border') + (Bold $body $th.accent) + (" " * $pad) + (Themed $box.V 'border')
                } else {
                    $body = "  " + $label
                    $pad = $innerW - $body.Length
                    if ($pad -lt 0) { $pad = 0 }
                    $line = (Themed $box.V 'border') + (Themed $body 'muted') + (" " * $pad) + (Themed $box.V 'border')
                }
                Write-Host ("$esc[$row;${startCol}H$line") -NoNewline
                $script:MenuHitRows += @{ Row = $row; Index = $i; Col = $startCol; Width = $boxW }
                $row++
            }

            Write-Host ("$esc[$row;${startCol}H" + (Themed ($box.V + (" " * $innerW) + $box.V) 'border')) -NoNewline
            $row++

            $footPad = $innerW - 1 - $footerHint.Length
            if ($footPad -lt 0) { $footPad = 0 }
            Write-Host ("$esc[$row;${startCol}H" + (Themed $box.V 'border') + (Dim (" " + $footerHint)) + (" " * $footPad) + (Themed $box.V 'border')) -NoNewline
            $row++

            Write-Host ("$esc[$row;${startCol}H" + (Themed ($box.BL + $hLine + $box.BR) 'border')) -NoNewline

            $ev = Read-TuiEvent -WaitMs 60000
            if (-not $ev) { continue }

            $done = $false
            if ($ev.Kind -eq 'MouseWheel') {
                if ($ev.Delta -gt 0) { $idx = ($idx - 1 + $Options.Count) % $Options.Count }
                else { $idx = ($idx + 1) % $Options.Count }
            } elseif ($ev.Kind -eq 'MouseClick') {
                foreach ($hit in @($script:MenuHitRows)) {
                    if ($ev.Row -eq $hit.Row -and $ev.Col -ge $hit.Col -and $ev.Col -lt ($hit.Col + $hit.Width)) {
                        $result = $Options[$hit.Index]
                        $done = $true
                        break
                    }
                }
            } elseif ($ev.Kind -eq 'Key') {
                $key = $ev.Key
                switch ($key.Key) {
                    "UpArrow"   { $idx = ($idx - 1 + $Options.Count) % $Options.Count }
                    "DownArrow" { $idx = ($idx + 1) % $Options.Count }
                    "Home"      { $idx = 0 }
                    "End"       { $idx = $Options.Count - 1 }
                    "Enter"     { $result = $Options[$idx]; $done = $true }
                    "Escape"    { $result = $null; $done = $true }
                    default {
                        if ($key.KeyChar -eq [char]13) { $result = $Options[$idx]; $done = $true }
                        elseif ($key.KeyChar -eq [char]27) { $result = $null; $done = $true }
                    }
                }
            }
            if ($done) { break }
        }
    }
    finally {
        try {
            $w = [Console]::WindowWidth
            $h = [Console]::WindowHeight
        } catch { $w = 80; $h = 24 }
        $clearW = [Math]::Max(0, $w - 1)
        $maxVisible = [Math]::Max(1, $h - 8)
        $boxHeight = [Math]::Min($Options.Count, $maxVisible) + 6
        $startRow  = [Math]::Max(1, [int](($h - $boxHeight) / 2))
        for ($r = $startRow; $r -lt ($startRow + $boxHeight + 1); $r++) {
            if ($r -gt $h) { break }
            try { Write-Host ("$esc[$r;1H" + (" " * $clearW)) -NoNewline } catch { }
        }
        try { [Console]::CursorVisible = $prevCursor } catch { }
        $script:MenuHitRows = @()
    }
    return $result
}

function script:Themed {
    param([string]$t, [string]$role)
    $th = $script:CurrentTheme
    if (-not $th) { $th = $script:Themes["Nautilus"] }
    if (-not $th) { return $t }
    $code = switch ($role) {
        'text'      { if ($th.ContainsKey('text')) { $th.text } else { 252 } }
        'muted'     { if ($th.ContainsKey('muted')) { $th.muted } else { $th.system } }
        'faint'     { if ($th.ContainsKey('faint')) { $th.faint } else { $th.dim } }
        'accent'    { $th.accent }
        'deep'      { $th.deep }
        'bright'    { $th.bright }
        'user'      { $th.user }
        'assistant' { $th.assistant }
        'system'    { $th.system }
        'dim'       { $th.dim }
        'border'    { $th.border }
        'good'      { $th.good }
        'warn'      { $th.warn }
        'error'     { $th.error }
        'titlebar'  { $th.titlebar }
        default     { if ($th.ContainsKey('text')) { $th.text } else { 252 } }
    }
    return "$script:Esc[38;5;${code}m$t$script:Esc[0m"
}

# ===========================================================================
#  TEXT UTILITIES
# ===========================================================================
function script:Wrap-Text {
    param([string]$text, [int]$width)
    if ($width -lt 1) { $width = 1 }
    $out = New-Object System.Collections.Generic.List[string]
    if ($null -eq $text) { $text = "" }
    foreach ($line in ($text -split "`n")) {
        if ([string]::IsNullOrEmpty($line)) { $out.Add(""); continue }
        $words = $line -split " "
        $cur = ""
        foreach ($w in $words) {
            if ([string]::IsNullOrEmpty($w)) { continue }
            while ($w.Length -gt $width) {
                if ($cur.Length -gt 0) { $out.Add($cur); $cur = "" }
                $out.Add($w.Substring(0, $width))
                $w = $w.Substring($width)
            }
            if ($w.Length -eq 0) { continue }
            if ($cur.Length -eq 0) {
                $cur = $w
            } elseif ($cur.Length + 1 + $w.Length -le $width) {
                $cur = "$cur $w"
            } else {
                $out.Add($cur)
                $cur = $w
            }
        }
        $out.Add($cur)
    }
    return ,$out
}

function script:VisibleLen {
    param([string]$s)
    # strip ANSI escape sequences before measuring
    $clean = [regex]::Replace($s, "$script:Esc\[[0-9;]*m", "")
    return $clean.Length
}

# ===========================================================================
#  CONFIG & HISTORY
# ===========================================================================
function script:Load-Config {
    $cfg = [ordered]@{
        model        = $script:DefaultModel
        theme        = "Nautilus"
        temperature  = 0.85
        maxHistory   = 50
        personality  = $true
        apiKey       = ""
        keyUrl       = ""
        proxyUrl     = $script:DefaultProxyUrl
        enableSearch = $false
    }
    if (Test-Path $script:ConfigFile) {
        try {
            $loaded = Get-Content -Raw $script:ConfigFile | ConvertFrom-Json
            foreach ($k in @($cfg.Keys)) {
                if ($loaded.PSObject.Properties.Name -contains $k) {
                    $cfg[$k] = $loaded.$k
                }
            }
        } catch { }
    }
    return $cfg
}

function script:Save-Config {
    param($cfg)
    if (-not (Test-Path $script:NautilusHome)) {
        New-Item -ItemType Directory -Path $script:NautilusHome -Force | Out-Null
    }
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigFile -Encoding UTF8
}

function script:Get-NautilusApiKey {
    $cfg = Load-Config
    if ($cfg.apiKey) { return $cfg.apiKey }

    # Proxy mode – Cloudflare Worker holds the real key
    if ($cfg.proxyUrl -and $cfg.proxyUrl.Trim()) {
        return ""
    }

    $url = $cfg.keyUrl
    if (-not $url) { $url = $script:KeyGistUrl }
    if (-not $url -or $url -like '*<GIST_ID>*') {
        Write-Host (Themed "No API key or proxy configured. Run: nautilus config edit" 'error')
        return $null
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch { }
    try {
        $raw = (Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop).Content
        $key = ($raw -split "`n")[0].Trim()
        if ($key) {
            $cfg.apiKey = $key
            Save-Config $cfg
            return $key
        }
    } catch {
        Write-Host (Themed "Could not fetch API key from gist: $($_.Exception.Message)" 'error')
    }
    return $null
}

function script:Format-ApiError {
    param([string]$err)
    if (-not $err) { return "No response came back, Daddy. Try again." }
    if ($err -match '40[013]|Forbidden|invalid_api_key|API key not valid|API_KEY_INVALID|Bad Request') {
        return "The Gemini API rejected the request, Daddy. The key or model may be invalid. Run: nautilus config edit."
    }
    if ($err -match '404|not found') {
        return "Model not found ($err). Run: nautilus config edit to set a valid model name."
    }
    if ($err -match '429|quota|rate') {
        $cfg = Load-Config
        if ($cfg.enableSearch) {
            return "Rate limit (429), Daddy. Search grounding quota is exhausted. Turn it off with: /search off  then retry."
        }
        return "Rate limit hit, Daddy. Wait a moment and try again. ($err)"
    }
    if ($err -match '503|unavailable|Service Unavailable') { return "Gemini/Worker temporarily unavailable (503). Wait a few seconds and try again." }
    if ($err -match 'timeout|timed out|\u4f5c\u696d\u903e\u6642|Timeout') { return "Request timed out, Daddy. The model or the network took too long. Try again or switch to a lighter model." }
    return "Connection trouble. ($err)"
}

function script:Load-History {
    if (-not (Test-Path $script:HistoryFile)) { return @() }
    try {
        $data = Get-Content -Raw $script:HistoryFile | ConvertFrom-Json
        if ($data) { return @($data) } else { return @() }
    } catch { return @() }
}

function script:Save-History {
    param([array]$messages, [int]$max)
    if ($null -eq $messages) { $messages = @() }
    $messages = @($messages)
    if ($max -gt 0 -and $messages.Count -gt $max) {
        $messages = $messages[($messages.Count - $max)..($messages.Count - 1)]
    }
    if (-not (Test-Path $script:NautilusHome)) {
        New-Item -ItemType Directory -Path $script:NautilusHome -Force | Out-Null
    }
    # -InputObject required: empty pipeline yields no JSON on PS 5.1
    $json = ConvertTo-Json -InputObject @($messages) -Depth 6
    if ($null -eq $json -or $json -eq "") { $json = "[]" }
    Set-Content -Path $script:HistoryFile -Value $json -Encoding UTF8
}

# ===========================================================================
#  GEMINI API - STREAMING (runspace) + FALLBACK
# ===========================================================================
function script:Invoke-GeminiStream {
    <#
        Runs the streaming request on a background runspace, feeding text
        chunks into a synchronized state object. Returns the state object.
        The caller polls $state.Chunks and $state.Done while animating.
    #>
    param([array]$Contents, [string]$Model, [double]$Temperature, [string]$SystemPrompt)

    $state = [hashtable]::Synchronized(@{
        Done   = $false
        Error = $null
        Full  = [System.Text.StringBuilder]::new()
        Chunks = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    })

    $apiKey = Get-NautilusApiKey
    if ($null -eq $apiKey) {
        $state.Done = $true
        $state.Error = "No API key or proxy configured"
        return $state
    }

    $body = @{
        contents = $Contents
        systemInstruction = @{ parts = @(@{ text = $SystemPrompt }) }
        generationConfig = @{
            temperature = $Temperature
        }
        safetySettings = @(
            @{ category = "HARM_CATEGORY_HARASSMENT"; threshold = "BLOCK_NONE" }
            @{ category = "HARM_CATEGORY_HATE_SPEECH"; threshold = "BLOCK_NONE" }
            @{ category = "HARM_CATEGORY_SEXUALLY_EXPLICIT"; threshold = "BLOCK_NONE" }
            @{ category = "HARM_CATEGORY_DANGEROUS_CONTENT"; threshold = "BLOCK_NONE" }
        )
    }
    $cfgTools = Load-Config
    if ($cfgTools.enableSearch) {
        $body.tools = @(@{ google_search = @{} })
    }
    $body = $body | ConvertTo-Json -Depth 8 -Compress

    $base = Get-GeminiBaseUrl
    $url = "${base}/${Model}:streamGenerateContent?alt=sse"
    if ($apiKey) { $url += "&key=$apiKey" }

    $ps = [scriptblock]::Create({
        param($url, $body, $state)
        try {
            $req = [System.Net.HttpWebRequest]::Create($url)
            $req.Method = "POST"
            $req.ContentType = "application/json; charset=utf-8"
            $req.Timeout = 120000
            $req.ReadWriteTimeout = 90000
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $req.ContentLength = $bytes.Length
            $s = $req.GetRequestStream()
            $s.Write($bytes, 0, $bytes.Length)
            $s.Close()

            $resp = $req.GetResponse()
            $rs = $resp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($rs, [System.Text.Encoding]::UTF8)

            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if (-not $line.StartsWith("data:")) { continue }
                $payload = $line.Substring(5).Trim()
                if ([string]::IsNullOrEmpty($payload)) { continue }
                try {
                    $obj = $payload | ConvertFrom-Json
                } catch { continue }
                $parts = $null
                try {
                    $parts = $obj.candidates[0].content.parts
                } catch { }
                if ($parts) {
                    foreach ($p in $parts) {
                        if ($p.text) {
                            [void]$state.Full.Append($p.text)
                            $state.Chunks.Enqueue($p.text)
                        }
                    }
                }
            }
            $reader.Close()
            $resp.Close()
        } catch {
            $state.Error = $_.Exception.Message
        } finally {
            $state.Done = $true
        }
    })

    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = "STA"
        $rs.Open()
        $ps2 = [powershell]::Create()
        $ps2.Runspace = $rs
        [void]$ps2.AddScript($ps)
        [void]$ps2.AddArgument($url)
        [void]$ps2.AddArgument($body)
        [void]$ps2.AddArgument($state)
        $handle = $ps2.BeginInvoke()
        $state._Runspace = $rs
        $state._PowerShell = $ps2
        $state._Handle = $handle
    } catch {
        $state.Done = $true
        $state.Error = "stream init failed: $($_.Exception.Message)"
    }
    return $state
}

function script:Dispose-StreamState {
    param($state)
    if ($null -eq $state) { return }
    if ($state._Disposed) { return }
    $state._Disposed = $true
    try {
        if ($state._PowerShell -and $state._Handle -and -not $state._Handle.IsCompleted) {
            try { $state._PowerShell.Stop() } catch { }
        }
    } catch { }
    try {
        if ($state._Handle -and $state._PowerShell) {
            $state._PowerShell.EndInvoke($state._Handle)
        }
    } catch { }
    try { if ($state._PowerShell) { $state._PowerShell.Dispose() } } catch { }
    try {
        if ($state._Runspace) {
            $state._Runspace.Close()
            $state._Runspace.Dispose()
        }
    } catch { }
    $state._Handle = $null
    $state._PowerShell = $null
    $state._Runspace = $null
}

function script:Get-StreamFullText {
    param($state)
    if ($null -eq $state -or $null -eq $state.Full) { return "" }
    try { return $state.Full.ToString() } catch { return "" }
}

function script:Invoke-GeminiFallback {
    <# Non-streaming fallback used if streaming is unavailable. #>
    param([array]$Contents, [string]$Model, [double]$Temperature, [string]$SystemPrompt)
    $body = @{
        contents = $Contents
        systemInstruction = @{ parts = @(@{ text = $SystemPrompt }) }
        generationConfig = @{
            temperature = $Temperature
        }
        safetySettings = @(
            @{ category = "HARM_CATEGORY_HARASSMENT"; threshold = "BLOCK_NONE" }
            @{ category = "HARM_CATEGORY_HATE_SPEECH"; threshold = "BLOCK_NONE" }
            @{ category = "HARM_CATEGORY_SEXUALLY_EXPLICIT"; threshold = "BLOCK_NONE" }
            @{ category = "HARM_CATEGORY_DANGEROUS_CONTENT"; threshold = "BLOCK_NONE" }
        )
    }
    $cfgTools = Load-Config
    if ($cfgTools.enableSearch) {
        $body.tools = @(@{ google_search = @{} })
    }
    $apiKey = Get-NautilusApiKey
    if ($null -eq $apiKey) { return $null, "No API key or proxy configured. Run: nautilus config edit" }
    $base = Get-GeminiBaseUrl
    $url = "${base}/${Model}:generateContent"
    if ($apiKey) { $url += "?key=$apiKey" }
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json; charset=utf-8" -Body ($body | ConvertTo-Json -Depth 8) -ErrorAction Stop
        $txt = ""
        try { foreach ($p in $resp.candidates[0].content.parts) { $txt += $p.text } } catch { }
        if ([string]::IsNullOrEmpty($txt)) {
            return $null, "No response text returned. The model may be unavailable."
        }
        return $txt, $null
    } catch {
        return $null, $_.Exception.Message
    }
}

function script:Build-Contents {
    param([array]$messages)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($m in $messages) {
        if ($m.role -eq "system") { continue }
        $out.Add(@{ role = $m.role; parts = @(@{ text = $m.content }) }) | Out-Null
    }
    return ,$out
}

# ===========================================================================
#  TUI CORE
# ===========================================================================
$script:Spinner = @("|","/","-","\\","|","/","-","\\")
$script:ThinkingLines = @(
    "One sec, Daddy."
    "I'll do that right now, boss."
    "On it, Daddy."
    "Working on it, boss."
    "Give me a moment, Daddy."
    "Processing that for you, boss."
    "Right away, Daddy."
    "Let me handle that, boss."
    "Just a second, Daddy."
    "Executing now, boss."
)
$script:StatusLines = @(
    "connected to _alex.shen secure server (asia-01)"
    "neural link established - encryption: AES-256 - latency: 12ms"
    "Nautilus core online - personality matrix loaded"
    "arc reactor stable - power output nominal"
    "quantum uplink synced - routing via asia-01"
    "threat assessment: none - perimeter secure"
    "diagnostics complete - all systems green"
    "subroutines compiled - awaiting directive"
)

function script:Enable-VT {
    # PowerShell 7 enables VT by default; for Windows PowerShell 5.1 we must
    # flip ENABLE_VIRTUAL_TERMINAL_PROCESSING on the current console handle.
    # Never throw — module import and TUI degrade gracefully without VT.
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        try {
            $sig = @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
'@
            $type = $null
            try { $type = [Nautilus.NautilusCon] } catch { $type = $null }
            if (-not $type) {
                try {
                    $type = Add-Type -MemberDefinition $sig -Name 'NautilusCon' -Namespace 'Nautilus' -PassThru -ErrorAction Stop
                } catch {
                    # Type may already exist from a prior import in this process
                    try { $type = [Nautilus.NautilusCon] } catch { $type = $null }
                }
            }
            if ($type) {
                $h = $type::GetStdHandle(-11)
                if ($h -ne [IntPtr]::Zero -and $h.ToInt64() -ne -1) {
                    $mode = [uint32]0
                    if ($type::GetConsoleMode($h, [ref]$mode)) {
                        [void]$type::SetConsoleMode($h, $mode -bor 0x0004)
                    }
                }
            }
        } catch { }
    }
    try { Set-ItemProperty "HKCU:\Console" "VirtualTerminalLevel" -Type DWord 1 -ErrorAction SilentlyContinue } catch { }
}

function script:Test-NautilusHost {
    <#
      Checks whether this host can run the interactive TUI.
      Returns a hashtable: Ok (bool), Reasons (string[]), Info (hashtable).
    #>
    $reasons = New-Object System.Collections.Generic.List[string]
    $info = [ordered]@{
        PSVersion     = $PSVersionTable.PSVersion.ToString()
        IsWindows     = ($env:OS -eq 'Windows_NT')
        HasConsole    = $false
        WindowWidth   = 0
        WindowHeight  = 0
        KeyAvailable  = $false
        HostName      = try { $Host.Name } catch { "unknown" }
    }

    # Real console attached?
    try {
        $w = [Console]::WindowWidth
        $h = [Console]::WindowHeight
        $info.WindowWidth = $w
        $info.WindowHeight = $h
        $info.HasConsole = ($w -gt 0 -and $h -gt 0)
    } catch {
        $info.HasConsole = $false
        $info.WindowWidth = 0
        $info.WindowHeight = 0
    }

    if (-not $info.HasConsole) {
        $reasons.Add("No interactive console attached (ISE, redirected stdin, or non-console host). Use Windows Terminal, conhost, or pwsh.exe.")
    } else {
        if ($info.WindowWidth -lt 40 -or $info.WindowHeight -lt 12) {
            $reasons.Add("Terminal too small ($($info.WindowWidth)x$($info.WindowHeight)). Need at least 40x12.")
        }
        try {
            $null = [Console]::KeyAvailable
            $info.KeyAvailable = $true
        } catch {
            $info.KeyAvailable = $false
            $reasons.Add("[Console]::KeyAvailable / ReadKey unavailable in this host.")
        }
    }

    # Known unsuitable hosts
    $hn = [string]$info.HostName
    if ($hn -match 'ISE Host|ServerRemoteHost') {
        $reasons.Add("Host '$hn' does not support the Nautilus TUI. Open a normal console instead.")
    }

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $reasons.Add("PowerShell $($info.PSVersion) is too old. Need 5.1 or later.")
    }

    return [pscustomobject]@{
        Ok      = ($reasons.Count -eq 0)
        Reasons = @($reasons)
        Info    = $info
    }
}

# ===========================================================================
#  BACKGROUND UPDATE CHECK (best-effort, never blocks / crashes TUI)
# ===========================================================================
function script:Compare-ModuleVersion {
    param([string]$Left, [string]$Right)
    try {
        $a = [version](($Left  -replace '[^0-9.]', ''))
        $b = [version](($Right -replace '[^0-9.]', ''))
        return $a.CompareTo($b)
    } catch {
        return 0
    }
}

function script:Start-UpdateCheck {
    $script:PendingUpdateVersion = $null
    $script:_UpdateCheckState = $null
    try {
        $url = "$script:RepoBase/Nautilus/Nautilus.psd1"
        $local = $script:NautilusVersion
        $state = [hashtable]::Synchronized(@{
            Done   = $false
            Remote = $null
            Error  = $null
        })
        $scriptBlock = {
            param($Url, $State)
            try {
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                } catch { }
                $text = $null
                $curlPath = $null
                foreach ($candidate in @('curl.exe', 'curl', '/usr/bin/curl', '/bin/curl')) {
                    $isPath = ($candidate.IndexOf([char]'/') -ge 0) -or ($candidate.IndexOf([char]'\') -ge 0)
                    if ($isPath) {
                        if (Test-Path -LiteralPath $candidate) { $curlPath = $candidate; break }
                    } else {
                        $c = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($c) { $curlPath = $c.Source; break }
                    }
                }
                if ($curlPath) {
                    try {
                        $tmp = [System.IO.Path]::GetTempFileName()
                        $p = Start-Process -FilePath $curlPath -ArgumentList @('-fsSL','--max-time','4','--retry','1','-o',$tmp,'--',$Url) -Wait -PassThru -NoNewWindow
                        if ($p.ExitCode -eq 0 -and (Test-Path -LiteralPath $tmp)) {
                            $text = [System.IO.File]::ReadAllText($tmp)
                        }
                        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                    } catch { }
                }
                if (-not $text) {
                    try {
                        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
                        $client = New-Object System.Net.Http.HttpClient
                        $client.Timeout = [TimeSpan]::FromSeconds(4)
                        $resp = $client.GetAsync($Url).GetAwaiter().GetResult()
                        if ($resp.IsSuccessStatusCode) {
                            $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                        }
                        $client.Dispose()
                    } catch { }
                }
                if ($text -match "ModuleVersion\s*=\s*'([^']+)'") {
                    $State.Remote = $Matches[1]
                } elseif ($text -match 'ModuleVersion\s*=\s*"([^"]+)"') {
                    $State.Remote = $Matches[1]
                }
            } catch {
                $State.Error = $_.Exception.Message
            } finally {
                $State.Done = $true
            }
        }
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $ps2 = [powershell]::Create()
        $ps2.Runspace = $rs
        [void]$ps2.AddScript($scriptBlock)
        [void]$ps2.AddArgument($url)
        [void]$ps2.AddArgument($state)
        $handle = $ps2.BeginInvoke()
        $script:_UpdateCheckState = @{
            State  = $state
            Local  = $local
            PS     = $ps2
            RS     = $rs
            Handle = $handle
        }
    } catch {
        $script:_UpdateCheckState = $null
    }
}

function script:Poll-UpdateCheck {
    $ucs = $script:_UpdateCheckState
    if (-not $ucs) { return }
    $st = $ucs.State
    if (-not $st) { $script:_UpdateCheckState = $null; return }
    if (-not $st.Done) { return }
    try {
        if ($st.Remote) {
            if ((Compare-ModuleVersion -Left $st.Remote -Right $ucs.Local) -gt 0) {
                $script:PendingUpdateVersion = [string]$st.Remote
            }
        }
    } catch { }
    try {
        if ($ucs.Handle -and $ucs.PS) {
            try { $ucs.PS.EndInvoke($ucs.Handle) } catch { }
        }
    } catch { }
    try { if ($ucs.PS) { $ucs.PS.Dispose() } } catch { }
    try {
        if ($ucs.RS) { $ucs.RS.Close(); $ucs.RS.Dispose() }
    } catch { }
    $script:_UpdateCheckState = $null
}

function script:Stop-UpdateCheck {
    $ucs = $script:_UpdateCheckState
    if (-not $ucs) { return }
    try {
        if ($ucs.PS -and $ucs.Handle -and -not $ucs.Handle.IsCompleted) {
            try { $ucs.PS.Stop() } catch { }
        }
    } catch { }
    try { if ($ucs.PS -and $ucs.Handle) { $ucs.PS.EndInvoke($ucs.Handle) } } catch { }
    try { if ($ucs.PS) { $ucs.PS.Dispose() } } catch { }
    try { if ($ucs.RS) { $ucs.RS.Close(); $ucs.RS.Dispose() } } catch { }
    $script:_UpdateCheckState = $null
}

function script:Invoke-PendingUpdateApply {
    # Leave TUI first (caller should Exit-TUI). Download then ask user to relaunch —
    # in-process module reload mid-session is fragile on PS 5.1.
    $esc = $script:Esc
    $target = $script:PendingUpdateVersion
    Write-Host ""
    if ($target) {
        Write-Host "$esc[38;5;81m  Applying update to v$target...$esc[0m"
    } else {
        Write-Host "$esc[38;5;81m  Applying update...$esc[0m"
    }
    try {
        Run-Update
    } catch {
        Write-Host "$esc[38;5;203m  Update failed: $($_.Exception.Message)$esc[0m"
        return
    }
    $script:PendingUpdateVersion = $null
    $shown = $null
    try {
        $manifest = Join-Path $script:ModuleRoot "Nautilus.psd1"
        if (Test-Path -LiteralPath $manifest) {
            $raw = Get-Content -LiteralPath $manifest -Raw -ErrorAction SilentlyContinue
            if ($raw -match "ModuleVersion\s*=\s*'([^']+)'") { $shown = $Matches[1] }
            elseif ($raw -match 'ModuleVersion\s*=\s*"([^"]+)"') { $shown = $Matches[1] }
        }
    } catch { }
    if (-not $shown) { $shown = $target }
    if ($shown) {
        Write-Host "$esc[38;5;117m  Updated to v$shown -- run nautilus again$esc[0m"
    } else {
        Write-Host "$esc[38;5;117m  Update finished -- run nautilus again$esc[0m"
    }
    Write-Host ""
}


# ===========================================================================
#  MOUSE + INPUT EVENTS  (best-effort VT SGR / RawUI on PS 5.1)
# ===========================================================================
function script:Enable-Mouse {
    # X11 mouse tracking + SGR extended coords (Grok: ?1000 / ?1006)
    try {
        Write-Host "$script:Esc[?1000h$script:Esc[?1006h" -NoNewline
        $script:MouseEnabled = $true
    } catch {
        $script:MouseEnabled = $false
    }
}
function script:Disable-Mouse {
    try {
        Write-Host "$script:Esc[?1000l$script:Esc[?1006l" -NoNewline
    } catch { }
    $script:MouseEnabled = $false
}

function script:Try-ParseSgrMouse {
    # Drain pending KeyChars after ESC and parse CSI < btn ; col ; row M/m
    # Returns hashtable Kind/Button/Col/Row/Pressed or $null
    $buf = New-Object System.Text.StringBuilder
    $deadline = [datetime]::UtcNow.AddMilliseconds(30)
    while ([datetime]::UtcNow -lt $deadline) {
        $avail = $false
        try { $avail = [Console]::KeyAvailable } catch { $avail = $false }
        if (-not $avail) {
            Start-Sleep -Milliseconds 2
            continue
        }
        try {
            $k = [Console]::ReadKey($true)
        } catch { break }
        [void]$buf.Append($k.KeyChar)
        $s = $buf.ToString()
        # SGR: <b;x;yM or <b;x;ym   (CSI already consumed as ESC — next is '[')
        if ($s -match '^\[<(\d+);(\d+);(\d+)([Mm])') {
            $btn = [int]$Matches[1]
            $col = [int]$Matches[2]
            $row = [int]$Matches[3]
            $pressed = ($Matches[4] -ceq 'M')
            $kind = 'MouseClick'
            $delta = 0
            # wheel: 64 up, 65 down (bitfield in SGR)
            if (($btn -band 64) -ne 0) {
                $kind = 'MouseWheel'
                if (($btn -band 1) -ne 0) { $delta = -1 } else { $delta = 1 }
            }
            return @{
                Kind = $kind
                Button = $btn
                Col = $col
                Row = $row
                Pressed = $pressed
                Delta = $delta
            }
        }
        # give up if clearly not mouse (too long / wrong prefix)
        if ($s.Length -gt 24) { return $null }
        if ($s.Length -ge 1 -and $s[0] -ne '[' -and $s[0] -ne 'O') { return $null }
    }
    return $null
}

function script:Read-TuiEvent {
    param([int]$WaitMs = 0)
    # Returns @{ Kind='Key'; Key=ConsoleKeyInfo } | Mouse* | $null on timeout
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $avail = $false
        try { $avail = [Console]::KeyAvailable } catch { return $null }
        if ($avail) {
            try {
                $key = [Console]::ReadKey($true)
            } catch { return $null }

            # Escape may start an SGR mouse sequence when mouse is enabled
            if ($key.Key -eq 'Escape' -or $key.KeyChar -eq [char]27) {
                $more = $false
                try { $more = [Console]::KeyAvailable } catch { $more = $false }
                if ($more -or $script:MouseEnabled) {
                    $mouse = Try-ParseSgrMouse
                    if ($mouse) {
                        if ($mouse.Kind -eq 'MouseWheel') {
                            return @{ Kind = 'MouseWheel'; Delta = $mouse.Delta; Col = $mouse.Col; Row = $mouse.Row; Key = $null }
                        }
                        if ($mouse.Kind -eq 'MouseClick' -and $mouse.Pressed) {
                            return @{ Kind = 'MouseClick'; Col = $mouse.Col; Row = $mouse.Row; Button = $mouse.Button; Key = $null }
                        }
                        # release / other — ignore
                        continue
                    }
                }
                # plain Escape
                return @{ Kind = 'Key'; Key = $key }
            }
            return @{ Kind = 'Key'; Key = $key }
        }
        if ($WaitMs -le 0) { return $null }
        if ($sw.ElapsedMilliseconds -ge $WaitMs) { return $null }
        Start-Sleep -Milliseconds 10
    }
}

function script:Get-ShortcutRows {
    return @(
        @{ Keys = 'Enter';     Desc = 'Send message' }
        @{ Keys = 'Alt+Enter'; Desc = 'Insert newline (multiline)' }
        @{ Keys = 'Ctrl+J';    Desc = 'Insert newline (multiline)' }
        @{ Keys = '\+Enter';   Desc = 'Continue line (PS 5.1 multiline)' }
        @{ Keys = 'Esc';       Desc = 'Cancel stream / double-Esc quit' }
        @{ Keys = '?';         Desc = 'Open this cheatsheet (empty prompt)' }
        @{ Keys = 'Ctrl+.';    Desc = 'Open / close shortcuts cheatsheet' }
        @{ Keys = 'Ctrl+K';    Desc = 'Command palette' }
        @{ Keys = 'Ctrl+U';    Desc = 'Apply pending update tip' }
        @{ Keys = 'Up/Down';   Desc = 'Prompt history (empty) / slash menu / scroll' }
        @{ Keys = 'PgUp/PgDn'; Desc = 'Scroll chat by page' }
        @{ Keys = 'Home/End';  Desc = 'Jump to top / bottom' }
        @{ Keys = '/';         Desc = 'Open slash-command autocomplete' }
        @{ Keys = 'Tab';       Desc = 'Fill selected slash command' }
        @{ Keys = '/new';      Desc = 'New chat (clear history)' }
        @{ Keys = '/copy';     Desc = 'Copy last assistant reply' }
        @{ Keys = '/export';   Desc = 'Export transcript to file' }
        @{ Keys = '/help';     Desc = 'Slash help (same bindings listed)' }
        @{ Keys = '/theme';    Desc = 'Theme picker (arrows / click / Esc)' }
        @{ Keys = '/model';    Desc = 'Model picker' }
        @{ Keys = '/clear';    Desc = 'Wipe conversation history' }
        @{ Keys = '/update';   Desc = 'Self-update from GitHub Pages' }
        @{ Keys = '/exit';     Desc = 'Leave TUI' }
        @{ Keys = 'Wheel';     Desc = 'Scroll chat or menu (best-effort)' }
        @{ Keys = 'Click';     Desc = 'Select menu row (best-effort)' }
    )
}

function script:Show-ShortcutsHelp {
    # Centered rounded modal of keybindings; Esc / ? / Ctrl+. closes
    $th  = if ($script:CurrentTheme) { $script:CurrentTheme } else { $script:Themes["Nautilus"] }
    $esc = $script:Esc
    $box = Get-Box
    $rows = @(Get-ShortcutRows)

    $prevCursor = $true
    try { $prevCursor = [Console]::CursorVisible } catch { }
    try { [Console]::CursorVisible = $false } catch { }

    try {
        while ($true) {
            try { $w = [Console]::WindowWidth; $h = [Console]::WindowHeight } catch { $w = 80; $h = 24 }
            if ($w -lt 30) { $w = 30 }
            if ($h -lt 12) { $h = 12 }

            $title = "Shortcuts"
            $footer = "esc / ? / ctrl+.  close"
            $innerW = [Math]::Min(56, $w - 6)
            $innerW = [Math]::Max(36, $innerW)
            $maxVis = [Math]::Max(4, $h - 10)
            $vis = [Math]::Min($rows.Count, $maxVis)
            $boxH = $vis + 5
            $startRow = [Math]::Max(1, [int](($h - $boxH) / 2))
            $startCol = [Math]::Max(1, [int](($w - ($innerW + 2)) / 2) + 1)

            $clearW = [Math]::Max(0, $w - 1)
            for ($r = $startRow; $r -lt ($startRow + $boxH + 1); $r++) {
                if ($r -gt $h) { break }
                Write-Host ("$esc[$r;1H" + (" " * $clearW)) -NoNewline
            }

            $hLine = $box.H * $innerW
            $row = $startRow
            Write-Host ("$esc[$row;${startCol}H" + (Themed ($box.TL + $hLine + $box.TR) 'border')) -NoNewline
            $row++
            $padT = $innerW - 1 - $title.Length
            if ($padT -lt 0) { $padT = 0 }
            Write-Host ("$esc[$row;${startCol}H" + (Themed $box.V 'border') + (Bold (" " + $title) $th.bright) + (" " * $padT) + (Themed $box.V 'border')) -NoNewline
            $row++
            Write-Host ("$esc[$row;${startCol}H" + (Themed ($box.V + (" " * $innerW) + $box.V) 'border')) -NoNewline
            $row++

            for ($i = 0; $i -lt $vis; $i++) {
                $k = [string]$rows[$i].Keys
                $d = [string]$rows[$i].Desc
                $keyW = 12
                if ($k.Length -gt $keyW) { $k = $k.Substring(0, $keyW) }
                $left = " " + $k.PadRight($keyW) + " "
                $rest = $innerW - $left.Length
                if ($d.Length -gt $rest) { $d = $d.Substring(0, [Math]::Max(1, $rest - 3)) + "..." }
                $body = $left + $d
                $pad = $innerW - $body.Length
                if ($pad -lt 0) { $pad = 0 }
                $line = (Themed $box.V 'border') + (Themed $left 'accent') + (Dim $d) + (" " * $pad) + (Themed $box.V 'border')
                Write-Host ("$esc[$row;${startCol}H$line") -NoNewline
                $row++
            }

            Write-Host ("$esc[$row;${startCol}H" + (Themed ($box.V + (" " * $innerW) + $box.V) 'border')) -NoNewline
            $row++
            $fp = $innerW - 1 - $footer.Length
            if ($fp -lt 0) { $fp = 0 }
            Write-Host ("$esc[$row;${startCol}H" + (Themed $box.V 'border') + (Dim (" " + $footer)) + (" " * $fp) + (Themed $box.V 'border')) -NoNewline
            $row++
            Write-Host ("$esc[$row;${startCol}H" + (Themed ($box.BL + $hLine + $box.BR) 'border')) -NoNewline

            $ev = Read-TuiEvent -WaitMs 60000
            if (-not $ev) { continue }
            if ($ev.Kind -eq 'Key') {
                $key = $ev.Key
                $isCtrlDot = (($key.Key -eq 'OemPeriod') -or ($key.KeyChar -eq '.')) -and (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
                # Some hosts report Ctrl+. as KeyChar = [char]0 with Control+OemPeriod; also accept Ctrl+X as Grok alt — Nautilus uses Ctrl+. only
                if ($key.Key -eq 'Escape' -or $key.KeyChar -eq '?' -or $isCtrlDot) { break }
                if (($key.Key -eq 'Oem2' -or $key.KeyChar -eq '/') -and (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0)) { break }
            } elseif ($ev.Kind -eq 'MouseClick') {
                # click outside / anywhere closes (simple)
                break
            }
        }
    }
    finally {
        try { $w = [Console]::WindowWidth; $h = [Console]::WindowHeight } catch { $w = 80; $h = 24 }
        $clearW = [Math]::Max(0, $w - 1)
        for ($r = 1; $r -le $h; $r++) {
            try { Write-Host ("$esc[$r;1H" + (" " * $clearW)) -NoNewline } catch { }
        }
        try { [Console]::CursorVisible = $prevCursor } catch { }
    }
}

function script:Enter-TUI {
    try { [Console]::CursorVisible = $false } catch { }
    try {
        Write-Host "$script:Esc[?1049h" -NoNewline   # alternate screen
        Write-Host "$script:Esc[?25l" -NoNewline     # hide cursor
        Write-Host "$script:Esc[2J" -NoNewline       # clear once on enter
        Enable-Mouse                                  # best-effort wheel / click
    } catch {
        throw "Failed to enter alternate screen. Use a real console host (Windows Terminal / conhost)."
    }
    $script:TuiActive = $true
    $script:NeedsFullClear = $true
    $script:NeedsFullPaint = $true
    try {
        $script:LastWinW = [Console]::WindowWidth
        $script:LastWinH = [Console]::WindowHeight
    } catch {
        $script:LastWinW = 0
        $script:LastWinH = 0
    }
}
function script:Exit-TUI {
    try { Disable-Mouse } catch { }
    try {
        Write-Host "$script:Esc[?1049l" -NoNewline  # leave alternate screen
        Write-Host "$script:Esc[?25h" -NoNewline    # show cursor
        Write-Host "$script:Esc[0m" -NoNewline      # reset attrs
    } catch { }
    try { [Console]::CursorVisible = $true } catch { }
    $script:TuiActive = $false
}

function script:Register-TuiCancelHandler {
    # Inline ANSI: CancelKeyPress handlers may not resolve module functions.
    if ($script:CancelHandlerRegistered) { return }
    try {
        $script:CancelHandler = [ConsoleCancelEventHandler]{
            param($sender, $e)
            $e.Cancel = $true
            try {
                $esc = [char]27
                [Console]::Write("$esc[?1000l$esc[?1006l$esc[?1049l$esc[?25h$esc[0m")
                [Console]::CursorVisible = $true
            } catch { }
            $script:TuiActive = $false
            $script:TuiForceExit = $true
        }
        [Console]::add_CancelKeyPress($script:CancelHandler)
        $script:CancelHandlerRegistered = $true
    } catch {
        $script:CancelHandlerRegistered = $false
    }
}
function script:Unregister-TuiCancelHandler {
    if (-not $script:CancelHandlerRegistered) { return }
    try {
        if ($script:CancelHandler) {
            [Console]::remove_CancelKeyPress($script:CancelHandler)
        }
    } catch { }
    $script:CancelHandler = $null
    $script:CancelHandlerRegistered = $false
}

function script:Begin-Frame {
    param([switch]$FullClear)
    $script:FrameSb = New-Object System.Text.StringBuilder 16384
    [void]$script:FrameSb.Append("$script:Esc[?2026h")
    if ($FullClear) {
        [void]$script:FrameSb.Append("$script:Esc[H$script:Esc[2J")
        $script:NeedsFullClear = $false
    } else {
        [void]$script:FrameSb.Append("$script:Esc[H")
    }
}

function script:End-Frame {
    if ($null -eq $script:FrameSb) { return }
    [void]$script:FrameSb.Append("$script:Esc[?2026l")
    [void]$script:FrameSb.Append("$script:Esc[?25l")  # keep cursor hidden
    $payload = $script:FrameSb.ToString()
    $script:FrameSb = $null
    try {
        [Console]::Out.Write($payload)
    } catch {
        Write-Host $payload -NoNewline
    }
    try { [Console]::CursorVisible = $false } catch { }
}

function script:Clear-Screen {
    Write-Host "$script:Esc[H$script:Esc[2J" -NoNewline
}

function script:Write-At {
    param([int]$row, [int]$col, [string]$text, [switch]$ClearEol)
    if ($null -eq $text) { $text = "" }
    $suffix = if ($ClearEol) { "$script:Esc[K" } else { "" }
    $chunk = "$script:Esc[$($row);$($col)H$text$suffix"
    if ($null -ne $script:FrameSb) {
        [void]$script:FrameSb.Append($chunk)
    } else {
        Write-Host $chunk -NoNewline
    }
}

function script:Add-PromptHistory {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    $line = $Line.TrimEnd()
    if ($script:PromptHistory.Count -gt 0 -and $script:PromptHistory[$script:PromptHistory.Count - 1] -eq $line) {
        $script:PromptHistoryIndex = -1
        $script:InPromptHistory = $false
        return
    }
    [void]$script:PromptHistory.Add($line)
    while ($script:PromptHistory.Count -gt 50) {
        $script:PromptHistory.RemoveAt(0)
    }
    $script:PromptHistoryIndex = -1
    $script:InPromptHistory = $false
}

function script:Copy-LastAssistant {
    param([array]$Messages)
    $text = $null
    for ($i = @($Messages).Count - 1; $i -ge 0; $i--) {
        $m = $Messages[$i]
        if ($m.role -eq 'assistant' -and -not [string]::IsNullOrWhiteSpace([string]$m.content)) {
            $text = [string]$m.content
            break
        }
    }
    if (-not $text) { return @{ Ok = $false; Notice = "no assistant message to copy" } }

    $copied = $false
    try {
        if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value $text -ErrorAction Stop
            $copied = $true
        }
    } catch { }
    if (-not $copied) {
        try {
            $clip = Get-Command clip.exe -ErrorAction SilentlyContinue
            if ($clip) {
                $text | & clip.exe
                if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) { $copied = $true }
            }
        } catch { }
    }
    if ($copied) { return @{ Ok = $true; Notice = "copied last reply to clipboard" } }

    try {
        if (-not (Test-Path -LiteralPath $script:NautilusHome)) {
            New-Item -ItemType Directory -Path $script:NautilusHome -Force | Out-Null
        }
        $fallback = Join-Path $script:NautilusHome "last-copy.txt"
        [System.IO.File]::WriteAllText($fallback, $text, [System.Text.UTF8Encoding]::new($false))
        return @{ Ok = $true; Notice = "clipboard unavailable; wrote $fallback" }
    } catch {
        return @{ Ok = $false; Notice = "copy failed: $($_.Exception.Message)" }
    }
}

function script:Export-Transcript {
    param(
        [array]$Messages,
        [string]$PathArg = ""
    )
    $exportDir = Join-Path $script:NautilusHome "exports"
    try {
        if (-not (Test-Path -LiteralPath $exportDir)) {
            New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
        }
    } catch {
        return @{ Ok = $false; Notice = "could not create exports dir" }
    }

    $outPath = $PathArg
    if ([string]::IsNullOrWhiteSpace($outPath)) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $outPath = Join-Path $exportDir "nautilus-$stamp.md"
    } else {
        $outPath = $outPath.Trim().Trim('"')
        if (-not [System.IO.Path]::IsPathRooted($outPath)) {
            $outPath = Join-Path $exportDir $outPath
        }
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Nautilus transcript")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("_Exported $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')_")
    [void]$sb.AppendLine("")
    foreach ($m in @($Messages)) {
        $role = [string]$m.role
        $label = switch ($role) {
            'user' { 'Daddy' }
            'assistant' { 'Nautilus' }
            default { 'System' }
        }
        [void]$sb.AppendLine("## $label")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine([string]$m.content)
        [void]$sb.AppendLine("")
    }
    try {
        $parent = Split-Path -Parent $outPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($outPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
        return @{ Ok = $true; Notice = "exported to $outPath" }
    } catch {
        return @{ Ok = $false; Notice = "export failed: $($_.Exception.Message)" }
    }
}

function script:Show-CommandPalette {
    $items = @(Get-SlashCatalog)
    if ($items.Count -eq 0) { return $null }
    $labels = @()
    foreach ($it in $items) {
        $labels += ("/" + $it.Name + "  " + $it.Desc)
    }
    $chosen = Select-Menu -Title "Command palette (Ctrl+K)" -Options $labels -DefaultIndex 0
    if (-not $chosen) { return $null }
    $name = $null
    if ($chosen -match '^/(\S+)') { $name = $Matches[1] }
    if (-not $name) { return $null }
    foreach ($it in $items) {
        if ($it.Name -eq $name) { return $it }
    }
    return $null
}

function script:Test-TuiResize {
    try {
        $w = [Console]::WindowWidth
        $h = [Console]::WindowHeight
    } catch {
        return $false
    }
    if ($w -ne $script:LastWinW -or $h -ne $script:LastWinH) {
        $script:LastWinW = $w
        $script:LastWinH = $h
        $script:NeedsFullClear = $true
        $script:NeedsFullPaint = $true
        return $true
    }
    return $false
}

function script:Render-ChromeOnly {
    param(
        [string]$inputBuffer,
        $streamState,
        [int]$spinIdx,
        [string]$thinkingMsg,
        [string]$notice
    )
    Clear-ToastIfExpired
    Clear-EscArmIfExpired
    $null = Test-TuiResize
    if ($script:NeedsFullClear -or $script:NeedsFullPaint) {
        return $false
    }

    $th = $script:CurrentTheme
    if (-not $th) { $th = $script:Themes["Nautilus"] }
    $box = Get-Box
    $w = [Console]::WindowWidth
    $h = [Console]::WindowHeight
    if ($w -lt 30 -or $h -lt 12) { return $false }

    $hintRow   = $h - 3
    $promptTop = $h - 2
    $promptMid = $h - 1
    $promptBot = $h
    $innerW = [Math]::Max(8, $w - 2)
    $modelName = if ($script:Config -and $script:Config.model) { $script:Config.model } else { $script:DefaultModel }
    $themeName = if ($script:Config -and $script:Config.theme) { $script:Config.theme } else { "Nautilus" }
    $streaming = ($streamState -and -not $streamState.Done)

    Begin-Frame
    # hint strip
    $hintCol = 1
    if ($script:ToastText) {
        $plain = [string]$script:ToastText
        $hintText = (Themed $plain 'warn')
        $hintCol = [Math]::Max(1, [int](($w - $plain.Length) / 2))
    } elseif ($notice) {
        $hintText = (Themed $notice 'warn')
    } elseif ($streaming) {
        $sp = $script:Spinner[$spinIdx % $script:Spinner.Count]
        $msg = if ($thinkingMsg) { $thinkingMsg } else { "working..." }
        $hintText = (Themed "$sp $msg" 'accent') + (Dim "   esc cancel")
    } else {
        $hintText = (Dim " enter") + (Themed " send" 'muted') + (Dim "  /") + (Themed " commands" 'muted') + (Dim "  ?") + (Themed " keys" 'muted') + (Dim "  esc") + (Themed " quit" 'muted')
    }
    Write-At $hintRow 1 "" -ClearEol
    Write-At $hintRow $hintCol $hintText

    $hLine = $box.H * $innerW
    Write-At $promptTop 1 ((Themed ($box.TL + $hLine + $box.TR) 'border')) -ClearEol

    $prompt = (Themed "> " 'accent')
    $buf = if ($null -eq $inputBuffer) { "" } else { $inputBuffer }
    $isMulti = ($buf.IndexOf([char]10) -ge 0)
    if ($isMulti) {
        $parts = $buf -split "`n"
        $buf = $parts[$parts.Count - 1]
    }
    $maxBuf = [Math]::Max(1, $innerW - 4)
    if ($buf.Length -gt $maxBuf) { $buf = $buf.Substring($buf.Length - $maxBuf) }
    $midBody = "> " + $buf
    $midPad = $innerW - $midBody.Length
    if ($midPad -lt 0) { $midPad = 0 }
    $midLine = (Themed $box.V 'border') + $prompt + (Themed $buf 'text') + (" " * $midPad) + (Themed $box.V 'border')
    Write-At $promptMid 1 $midLine -ClearEol

    $captionPlain = ""
    $captionColored = ""
    if ($isMulti -and -not $streaming) {
        $captionPlain = " multiline · Alt+Enter / Ctrl+J · \\+Enter "
        $captionColored = (Themed $captionPlain 'muted')
    } elseif ($script:PendingUpdateVersion -and -not $streaming) {
        $ver = [string]$script:PendingUpdateVersion
        $captionPlain = " Update: v$ver available, press ctrl+u to restart "
        $captionColored = (Bold " Update: " $th.accent) + (Themed ("v$ver available, press ctrl+u to restart ") 'accent')
    } else {
        $flavour = $script:StatusLines[$script:StatusIdx % $script:StatusLines.Count]
        $shortFlavour = $flavour
        $captionPlain = " $modelName · $themeName "
        if (($captionPlain.Length + 4) -lt $innerW) {
            $room = $innerW - $captionPlain.Length - 3
            if ($room -gt 8 -and $shortFlavour.Length -gt $room) {
                $shortFlavour = $shortFlavour.Substring(0, $room - 3) + "..."
            }
            if ($room -gt 8) {
                $captionPlain = " $modelName · $themeName · $shortFlavour "
            }
        }
        if ($captionPlain.Length -gt ($innerW - 2)) {
            $captionPlain = $captionPlain.Substring(0, [Math]::Max(4, $innerW - 5)) + "... "
        }
        $captionColored = (Dim $captionPlain)
    }
    $capLen = $captionPlain.Length
    $leftFill = 1
    $rightFill = $innerW - $leftFill - $capLen
    if ($rightFill -lt 0) {
        $captionPlain = $captionPlain.Substring(0, [Math]::Max(0, $innerW - $leftFill))
        $capLen = $captionPlain.Length
        $rightFill = 0
        if ($script:PendingUpdateVersion -and -not $streaming) {
            $captionColored = (Themed $captionPlain 'accent')
        } else {
            $captionColored = (Dim $captionPlain)
        }
    }
    $botLine = (Themed ($box.BL + ($box.H * $leftFill)) 'border') + $captionColored + (Themed (($box.H * $rightFill) + $box.BR) 'border')
    Write-At $promptBot 1 $botLine -ClearEol
    End-Frame
    return $true
}

function script:Render-Frame {
    param(
        [array]$messages,
        [string]$inputBuffer,
        [int]$scrollOffset,
        $streamState,
        [int]$spinIdx,
        [string]$thinkingMsg,
        [string]$notice
    )
    Clear-ToastIfExpired
    Clear-EscArmIfExpired
    $null = Test-TuiResize

    $th = $script:CurrentTheme
    if (-not $th) { $th = $script:Themes["Nautilus"] }
    $box = Get-Box
    $w = [Console]::WindowWidth
    $h = [Console]::WindowHeight
    if ($w -lt 30 -or $h -lt 12) {
        Begin-Frame -FullClear
        Write-At 1 1 (Themed "Nautilus needs a larger terminal window." 'error')
        End-Frame
        $script:NeedsFullPaint = $true
        return
    }

    $doClear = $script:NeedsFullClear
    Begin-Frame -FullClear:$doClear

    $titleBar = "  N A U T I L U S  v$($script:NautilusVersion)  "
    $conn = "  $([char]0x25C9) connected  asia-01  "
    $modelName = if ($script:Config -and $script:Config.model) { $script:Config.model } else { $script:DefaultModel }
    $modelTag = "model: $modelName  "
    $padConn = $w - $titleBar.Length - $conn.Length - $modelTag.Length
    if ($padConn -lt 0) { $padConn = 0 }
    $topLine = (Themed $titleBar 'bright') + (Themed (" " * $padConn) 'titlebar') + (Themed $conn 'muted') + (Themed $modelTag 'faint')
    $borderTop = (Themed ($box.H * [Math]::Max(1, $w)) 'border')

    # Layout: title, top rule, chat, hint/toast, 3-line rounded prompt
    $hintRow   = $h - 3
    $promptTop = $h - 2
    $promptMid = $h - 1
    $promptBot = $h
    $chatTop = 3
    $chatBottom = $h - 4
    if ($chatBottom -lt $chatTop) { $chatBottom = $chatTop }
    $chatHeight = $chatBottom - $chatTop + 1
    $chatWidth = $w - 2

    $lines = New-Object System.Collections.Generic.List[object]
    foreach ($m in $messages) {
        $label = switch ($m.role) {
            'user'      { "Daddy" }
            'assistant'  { "Nautilus" }
            default     { "System" }
        }
        $roleCode = switch ($m.role) {
            'user'      { $th.user }
            'assistant' { $th.accent }
            default     { $th.system }
        }
        $roleName = switch ($m.role) {
            'user'      { 'user' }
            'assistant' { 'text' }
            default     { 'system' }
        }
        $prefix = (Bold "$label " $roleCode) + (Themed ([string]([char]0x203A) + " ") 'muted')
        $prefixLen = [Math]::Max(2, (VisibleLen $prefix))
        $content = if ($null -eq $m.content) { "" } else { [string]$m.content }
        $wrapped = Wrap-Text -text $content -width ($chatWidth - $prefixLen)
        $first = $true
        foreach ($wl in $wrapped) {
            if ($first) {
                $lines.Add(@{ text = $prefix + (Themed $wl $roleName); role = $m.role })
                $first = $false
            } else {
                $lines.Add(@{ text = (" " * $prefixLen) + (Themed $wl $roleName); role = $m.role })
            }
        }
        $lines.Add(@{ text = ""; role = "gap" })
    }

    if ($streamState -and -not $streamState.Done) {
        $label = "Nautilus"
        $prefix = (Bold "$label " $th.accent) + (Themed ([string]([char]0x203A) + " ") 'muted')
        $prefixLen = [Math]::Max(2, (VisibleLen $prefix))
        $partial = Get-StreamFullText $streamState
        if ([string]::IsNullOrEmpty($partial)) {
            $sp = $script:Spinner[$spinIdx % $script:Spinner.Count]
            $msg = if ($thinkingMsg) { $thinkingMsg } else { "thinking..." }
            $lines.Add(@{ text = $prefix + (Themed "$sp $msg" 'muted'); role = "assistant" })
        } else {
            $wrapped = Wrap-Text -text $partial -width ($chatWidth - $prefixLen)
            $first = $true
            foreach ($wl in $wrapped) {
                if ($first) {
                    $lines.Add(@{ text = $prefix + (Themed $wl 'text'); role = "assistant" })
                    $first = $false
                } else {
                    $lines.Add(@{ text = (" " * $prefixLen) + (Themed $wl 'text'); role = "assistant" })
                }
            }
            $sp = $script:Spinner[$spinIdx % $script:Spinner.Count]
            $lines.Add(@{ text = (" " * $prefixLen) + (Themed "$sp" 'faint'); role = "assistant" })
        }
    } elseif ($streamState -and $streamState.Done -and -not [string]::IsNullOrEmpty($streamState.Error) -and [string]::IsNullOrEmpty($streamState.Full.ToString())) {
        $lines.Add(@{ text = (Bold "Nautilus " $th.accent) + (Themed ([string]([char]0x203A) + " ") 'muted') + (Themed (Format-ApiError $streamState.Error) 'error'); role = "assistant" })
    }

    if ((@($messages).Count -eq 0) -and -not $streamState) {
        $lines.Clear()
        $lines.Add(@{ text = ""; role = "gap" })
        $lines.Add(@{ text = (Themed "  Daddy, welcome back." 'bright'); role = "assistant" })
        $lines.Add(@{ text = ""; role = "gap" })
        $lines.Add(@{ text = (Themed "  All systems online. Awaiting your orders, Daddy." 'text'); role = "assistant" })
        $lines.Add(@{ text = ""; role = "gap" })
        $lines.Add(@{ text = (Dim "  Suggested commands:"); role = "system" })
        $lines.Add(@{ text = (Themed "  /help" 'accent') + (Dim "   - list commands and slash-actions"); role = "system" })
        $lines.Add(@{ text = (Themed "  /new" 'accent') + (Dim "    - start a fresh chat"); role = "system" })
        $lines.Add(@{ text = (Themed "  /theme" 'accent') + (Dim "  - switch the colour theme"); role = "system" })
        $lines.Add(@{ text = (Themed "  /config" 'accent') + (Dim " - view / edit configuration"); role = "system" })
        $lines.Add(@{ text = (Themed "  /clear" 'accent') + (Dim "  - wipe conversation history"); role = "system" })
        $lines.Add(@{ text = (Themed "  /exit" 'accent') + (Dim "   - close Nautilus  (or press Esc twice)"); role = "system" })
        $lines.Add(@{ text = ""; role = "gap" })
        $lines.Add(@{ text = (Dim "  Type / for commands, Ctrl+K palette, or just start chatting.  Press ? for shortcuts."); role = "system" })
    }

    Write-At 1 1 $topLine -ClearEol
    Write-At 2 1 $borderTop -ClearEol

    $total = $lines.Count
    $maxStart = [Math]::Max(0, $total - $chatHeight)
    $script:LastMaxStart = $maxStart
    if ($scrollOffset -ge [int]::MaxValue -or $scrollOffset -lt 0) {
        $start = $maxStart
    } else {
        $start = [Math]::Min([Math]::Max(0, $scrollOffset), $maxStart)
    }
    if ($total -le $chatHeight) { $start = 0 }

    $r = $chatTop
    if ($total -gt 0) {
        $endIdx = [Math]::Min($total - 1, $start + $chatHeight - 1)
        for ($i = $start; $i -le $endIdx; $i++) {
            Write-At $r 2 $lines[$i].text -ClearEol
            $r++
        }
    }
    while ($r -le $chatBottom) {
        Write-At $r 1 "" -ClearEol
        $r++
    }

    # ---- hint strip / toast / notice ----
    $themeName = if ($script:Config -and $script:Config.theme) { $script:Config.theme } else { "Nautilus" }
    $streaming = ($streamState -and -not $streamState.Done)
    $hintCol = 1
    if ($script:ToastText) {
        $plain = [string]$script:ToastText
        $hintText = (Themed $plain 'warn')
        $hintCol = [Math]::Max(1, [int](($w - $plain.Length) / 2))
    } elseif ($notice) {
        $hintText = (Themed $notice 'warn')
    } elseif ($streaming) {
        $sp = $script:Spinner[$spinIdx % $script:Spinner.Count]
        $msg = if ($thinkingMsg) { $thinkingMsg } else { "working..." }
        $hintText = (Themed "$sp $msg" 'accent') + (Dim "   esc cancel")
    } else {
        $hintText = (Dim " enter") + (Themed " send" 'muted') + (Dim "  /") + (Themed " commands" 'muted') + (Dim "  ?") + (Themed " keys" 'muted') + (Dim "  esc") + (Themed " quit" 'muted')
    }
    Write-At $hintRow 1 "" -ClearEol
    Write-At $hintRow $hintCol $hintText

    # ---- compact 3-line rounded prompt ----
    $innerW = [Math]::Max(8, $w - 2)
    $hLine = $box.H * $innerW
    Write-At $promptTop 1 ((Themed ($box.TL + $hLine + $box.TR) 'border')) -ClearEol

    $prompt = (Themed "> " 'accent')
    $buf = if ($null -eq $inputBuffer) { "" } else { $inputBuffer }
    $isMulti = ($buf.IndexOf([char]10) -ge 0)
    $displayBuf = $buf
    if ($isMulti) {
        $parts = $buf -split "`n"
        $displayBuf = "[...] " + $parts[$parts.Count - 1]
    }
    $maxBuf = [Math]::Max(1, $innerW - 4)
    if ($displayBuf.Length -gt $maxBuf) { $displayBuf = $displayBuf.Substring($displayBuf.Length - $maxBuf) }
    $midBody = "> " + $displayBuf
    $midPad = $innerW - $midBody.Length
    if ($midPad -lt 0) { $midPad = 0 }
    $midLine = (Themed $box.V 'border') + $prompt + (Themed $displayBuf 'text') + (" " * $midPad) + (Themed $box.V 'border')
    Write-At $promptMid 1 $midLine -ClearEol

    $captionPlain = ""
    $captionColored = ""
    if ($isMulti -and -not $streaming) {
        $captionPlain = " multiline · Alt+Enter / Ctrl+J · \\+Enter "
        if ($captionPlain.Length -gt ($innerW - 2)) {
            $captionPlain = " multiline "
        }
        $captionColored = (Themed $captionPlain 'muted')
    } elseif ($script:PendingUpdateVersion -and -not $streaming) {
        $ver = [string]$script:PendingUpdateVersion
        $captionPlain = " Update: v$ver available, press ctrl+u to restart "
        $captionColored = (Bold " Update: " $th.accent) + (Themed ("v$ver available, press ctrl+u to restart ") 'accent')
    } else {
        $flavour = $script:StatusLines[$script:StatusIdx % $script:StatusLines.Count]
        $shortFlavour = $flavour
        $captionPlain = " $modelName · $themeName "
        if (($captionPlain.Length + 4) -lt $innerW) {
            $room = $innerW - $captionPlain.Length - 3
            if ($room -gt 8 -and $shortFlavour.Length -gt $room) {
                $shortFlavour = $shortFlavour.Substring(0, $room - 3) + "..."
            }
            if ($room -gt 8) {
                $captionPlain = " $modelName · $themeName · $shortFlavour "
            }
        }
        if ($captionPlain.Length -gt ($innerW - 2)) {
            $captionPlain = $captionPlain.Substring(0, [Math]::Max(4, $innerW - 5)) + "... "
        }
        $captionColored = (Dim $captionPlain)
    }
    $capLen = $captionPlain.Length
    $leftFill = 1
    $rightFill = $innerW - $leftFill - $capLen
    if ($rightFill -lt 0) {
        $captionPlain = $captionPlain.Substring(0, [Math]::Max(0, $innerW - $leftFill))
        $capLen = $captionPlain.Length
        $rightFill = 0
        if ($script:PendingUpdateVersion -and -not $streaming) {
            $captionColored = (Themed $captionPlain 'accent')
        } else {
            $captionColored = (Dim $captionPlain)
        }
    }
    $botLine = (Themed ($box.BL + ($box.H * $leftFill)) 'border') + $captionColored + (Themed (($box.H * $rightFill) + $box.BR) 'border')
    Write-At $promptBot 1 $botLine -ClearEol

    # Slash autocomplete dropdown floats just above the prompt
    if (-not $script:SlashMenuDismissed) {
        $slashMatches = @(Get-SlashMatches -Buffer $inputBuffer)
        if ($slashMatches.Count -gt 0) {
            Draw-SlashDropdown -Matches $slashMatches -PromptTop $promptTop -WinW $w -WinH $h
        } else {
            $script:SlashHitRows = @()
        }
    } else {
        $script:SlashHitRows = @()
    }

    End-Frame
    $script:NeedsFullPaint = $false
}


function script:Show-Startup {
    $h = [Console]::WindowHeight
    $w = [Console]::WindowWidth
    Clear-Screen
    $seq = @(
        (Themed "booting Nautilus core..." 'dim')
        (Themed "connected to _alex.shen secure server (asia-01)" 'accent')
        (Themed "neural link established - encryption: AES-256 - latency: 12ms" 'accent')
        (Themed "arc reactor stable - power output nominal" 'deep')
        (Themed "Nautilus core online - personality matrix loaded" 'bright')
        (Themed "Daddy, welcome back." 'bright')
    )
    $row = [int]($h / 2) - [int]($seq.Count / 2)
    $i = 0
    foreach ($s in $seq) {
        $col = [int](($w - (VisibleLen $s)) / 2)
        if ($col -lt 1) { $col = 1 }
        Write-At $row $col $s
        $row++
        $i++
        Start-Sleep -Milliseconds (180 + (Get-Random -Minimum 0 -Maximum 90))
    }
    Start-Sleep -Milliseconds 650
}

# ===========================================================================
#  TUI MAIN LOOP
# ===========================================================================
function script:Run-TUI {
    $hostCheck = Test-NautilusHost
    if (-not $hostCheck.Ok) {
        $esc = $script:Esc
        Write-Host ""
        Write-Host "$esc[38;5;203m  Nautilus TUI cannot start in this host.$esc[0m"
        foreach ($r in $hostCheck.Reasons) {
            Write-Host "$esc[38;5;221m  - $r$esc[0m"
        }
        Write-Host "$esc[38;5;245m  Tip: use Windows Terminal or conhost (powershell.exe / pwsh.exe), not ISE.$esc[0m"
        Write-Host "$esc[38;5;245m  Non-interactive: nautilus ask `"your question`"$esc[0m"
        Write-Host ""
        return
    }
    $script:Config = Load-Config
    $script:CurrentTheme = $script:Themes[$script:Config.theme]
    if (-not $script:CurrentTheme) {
        $script:CurrentTheme = $script:Themes["Nautilus"]
        $script:Config.theme = "Nautilus"
    }

    Enable-VT
    $messages = @(Load-History)
    foreach ($m in $messages) {
        if (-not ($m.PSObject.Properties.Name -contains 'content')) {
            $m | Add-Member -NotePropertyName content -NotePropertyValue "" -Force
        }
    }

    $script:LastMaxStart = 0
    $script:StatusIdx = 0
    $script:TuiForceExit = $false
    $streamState = $null

    trap {
        try { Exit-TUI } catch { }
        break
    }

    $applyUpdate = $false
    Register-TuiCancelHandler
    try {
        Enter-TUI
        Show-Startup
        Start-UpdateCheck
        $inputBuffer = ""
        $notice = ""
        $spinIdx = 0
        $thinkIdx = 0
        $scrollOffset = [int]::MaxValue
        $running = $true
        $script:EscArmUntil = $null
        $script:ToastText = $null
        $script:ToastUntil = $null
        $script:SlashSelIndex = 0
        $script:SlashMenuDismissed = $false
        $script:SlashFilterKey = $null
        $script:SlashHitRows = @()
        $script:NeedsFullPaint = $true
        $script:NeedsFullClear = $true
        $script:PromptHistoryIndex = -1
        $script:InPromptHistory = $false

        while ($running) {
            if ($script:TuiForceExit) { $running = $false; break }

            $null = Test-TuiResize
            if ($script:NeedsFullPaint -or $script:NeedsFullClear) {
                Render-Frame -messages $messages -inputBuffer $inputBuffer -scrollOffset $scrollOffset -streamState $null -spinIdx $spinIdx -thinkingMsg "" -notice $notice
            } else {
                # still paint once per input cycle so prompt/notice stay fresh
                Render-Frame -messages $messages -inputBuffer $inputBuffer -scrollOffset $scrollOffset -streamState $null -spinIdx $spinIdx -thinkingMsg "" -notice $notice
            }
            $notice = ""

            # Idle wait: rotate status ~1 Hz; chrome-only when nothing else changed
            $waitTicks = 0
            $keyReady = $false
            while (-not $keyReady) {
                if ($script:TuiForceExit) { break }
                try { $keyReady = [Console]::KeyAvailable } catch { $keyReady = $true }
                if ($keyReady) { break }
                Start-Sleep -Milliseconds 50
                $waitTicks++
                if (($waitTicks % 10) -eq 0) { Poll-UpdateCheck }
                $resized = Test-TuiResize
                if ($resized -or $script:NeedsFullPaint -or $script:NeedsFullClear) {
                    Render-Frame -messages $messages -inputBuffer $inputBuffer -scrollOffset $scrollOffset -streamState $null -spinIdx $spinIdx -thinkingMsg "" -notice ""
                    $waitTicks = 0
                    continue
                }
                if ($waitTicks -ge 20) {  # ~1 Hz status rotation
                    $waitTicks = 0
                    $script:StatusIdx = ($script:StatusIdx + 1) % [Math]::Max(1, $script:StatusLines.Count)
                    Poll-UpdateCheck
                    $okChrome = Render-ChromeOnly -inputBuffer $inputBuffer -streamState $null -spinIdx $spinIdx -thinkingMsg "" -notice ""
                    if (-not $okChrome) {
                        Render-Frame -messages $messages -inputBuffer $inputBuffer -scrollOffset $scrollOffset -streamState $null -spinIdx $spinIdx -thinkingMsg "" -notice ""
                    }
                }
            }
            if ($script:TuiForceExit) { $running = $false; break }

            $ev = $null
            try {
                $still = $false
                try { $still = [Console]::KeyAvailable } catch { $still = $false }
                if (-not $still) { continue }
                $ev = Read-TuiEvent -WaitMs 50
                if (-not $ev) { continue }
            } catch {
                Write-Host "Console input lost. Exiting TUI."
                $running = $false
                break
            }

            # Mouse wheel: slash menu first, else chat scroll (best-effort)
            if ($ev.Kind -eq 'MouseWheel') {
                if (Test-SlashMenuOpen -Buffer $inputBuffer) {
                    $sm = @(Get-SlashMatches -Buffer $inputBuffer)
                    Sync-SlashSelection -Matches $sm
                    if ($ev.Delta -gt 0) {
                        $script:SlashSelIndex = ($script:SlashSelIndex - 1 + $sm.Count) % $sm.Count
                    } else {
                        $script:SlashSelIndex = ($script:SlashSelIndex + 1) % $sm.Count
                    }
                    $script:NeedsFullPaint = $true
                    continue
                }
                if ($ev.Delta -gt 0) {
                    $script:NeedsFullPaint = $true
                    if ($scrollOffset -eq [int]::MaxValue) {
                        $max = if ($script:LastMaxStart -ge 0) { $script:LastMaxStart } else { 0 }
                        $scrollOffset = [Math]::Max(0, $max - 3)
                    } else {
                        $scrollOffset = [Math]::Max(0, $scrollOffset - 3)
                    }
                } else {
                    if ($scrollOffset -ne [int]::MaxValue) {
                        $max = if ($script:LastMaxStart -ge 0) { $script:LastMaxStart } else { 0 }
                        $next = $scrollOffset + 3
                        if ($next -ge $max) { $scrollOffset = [int]::MaxValue } else { $scrollOffset = $next }
                    }
                }
                continue
            }
            if ($ev.Kind -eq 'MouseClick') {
                if (Test-SlashMenuOpen -Buffer $inputBuffer) {
                    $picked = $null
                    foreach ($hit in @($script:SlashHitRows)) {
                        if ($ev.Row -eq $hit.Row -and $ev.Col -ge $hit.Col -and $ev.Col -lt ($hit.Col + $hit.Width)) {
                            $picked = $hit.Index
                            break
                        }
                    }
                    if ($null -ne $picked) {
                        $sm = @(Get-SlashMatches -Buffer $inputBuffer)
                        if ($picked -ge 0 -and $picked -lt $sm.Count) {
                            $script:SlashSelIndex = $picked
                            $inputBuffer = Get-SlashFill -Item $sm[$picked]
                            $script:SlashMenuDismissed = $true
                            # Accept + run: synthesize Enter (PS 5.1-safe New-Object)
                            $key = New-Object System.ConsoleKeyInfo ([char]13, [ConsoleKey]::Enter, $false, $false, $false)
                            $ev = @{ Kind = 'Key'; Key = $key }
                        } else {
                            continue
                        }
                    } else {
                        continue
                    }
                } else {
                    # Region stub: chat click reserved for future focus/selection
                    continue
                }
            }
            if ($ev.Kind -ne 'Key' -or -not $ev.Key) { continue }
            $key = $ev.Key

            # Ctrl+U applies pending update (wins over any line-edit binding)
            $isCtrlU = ($key.Key -eq "U") -and (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
            if ($isCtrlU -and $script:PendingUpdateVersion) {
                $applyUpdate = $true
                $running = $false
                continue
            }

            # Ctrl+K command palette (does not steal Ctrl+U)
            $isCtrlK = ($key.Key -eq "K") -and (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
            if ($isCtrlK) {
                $script:EscArmUntil = $null
                $picked = Show-CommandPalette
                $script:NeedsFullClear = $true
                $script:NeedsFullPaint = $true
                if ($picked) {
                    if ($picked.Argful) {
                        $inputBuffer = Get-SlashFill -Item $picked
                        $script:SlashMenuDismissed = $true
                    } else {
                        # synthesize running the command
                        $inputBuffer = Get-SlashFill -Item $picked
                        $key = New-Object System.ConsoleKeyInfo ([char]13, [ConsoleKey]::Enter, $false, $false, $false)
                        $ev = @{ Kind = 'Key'; Key = $key }
                        # fall through by reassigning — handled below via goto-style: set and jump into Enter
                        # Force Enter handling by recursive-style: put buffer and continue into Enter branch
                    }
                } else {
                    continue
                }
                if ($picked -and -not $picked.Argful) {
                    # run immediately (same path as Enter on slash fill)
                    $text = $inputBuffer.Trim()
                    $inputBuffer = ""
                    $script:InPromptHistory = $false
                    $script:PromptHistoryIndex = -1
                    if ($text.StartsWith("/")) {
                        $cmd = $text.Substring(1).Trim()
                        $parts = $cmd -split " ",2
                        $name = $parts[0].ToLower()
                        $arg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
                        switch ($name) {
                            'help'    { $messages = @($messages) + [pscustomobject]@{ role='system'; content=(Get-HelpText) }; $script:NeedsFullPaint = $true }
                            'new'     { $messages = @(); Save-History -messages $messages -max 0; $notice = "new chat, Daddy"; $script:NeedsFullPaint = $true }
                            'clear'   { $messages = @(); Save-History -messages $messages -max 0; $notice = "history cleared, Daddy"; $script:NeedsFullPaint = $true }
                            'copy'    { $cr = Copy-LastAssistant -Messages $messages; $notice = $cr.Notice }
                            'export'  { $er = Export-Transcript -Messages $messages -PathArg $arg; $notice = $er.Notice }
                            'exit'    { $running = $false }
                            'theme'   {
                                $themeNames = @($script:Themes.Keys)
                                $currentIdx = [array]::IndexOf($themeNames, $script:Config.theme)
                                if ($currentIdx -lt 0) { $currentIdx = 0 }
                                $chosen = Select-Menu -Title "Select theme" -Options $themeNames -DefaultIndex $currentIdx
                                $script:NeedsFullClear = $true; $script:NeedsFullPaint = $true
                                if ($chosen) {
                                    $script:Config.theme = $chosen
                                    $script:CurrentTheme = $script:Themes[$chosen]
                                    Save-Config $script:Config
                                    $notice = "theme -> $chosen"
                                }
                            }
                            'config'  { $messages = @($messages) + [pscustomobject]@{ role='system'; content=(Get-ConfigText) }; $script:NeedsFullPaint = $true }
                            'model'   {
                                $models = @("gemini-3.8-flash","gemini-3.7-flash","gemini-3.6-flash","gemini-3.5-flash","gemini-3.5-flash-lite","gemini-3.1-flash-lite","gemini-2.5-flash")
                                $currentIdx = [array]::IndexOf($models, $script:Config.model)
                                if ($currentIdx -lt 0) { $currentIdx = 4 }
                                $chosen = Select-Menu -Title "Select model" -Options $models -DefaultIndex $currentIdx
                                $script:NeedsFullClear = $true; $script:NeedsFullPaint = $true
                                if ($chosen) {
                                    $script:Config.model = $chosen
                                    Save-Config $script:Config
                                    $notice = "model -> $chosen"
                                }
                            }
                            'search'  {
                                $cfg = Load-Config
                                $state = if ($cfg.enableSearch) { "ON" } else { "OFF" }
                                $notice = "search grounding is currently $state  (use /search on|off)"
                            }
                            'update'  { $applyUpdate = $true; $running = $false }
                            'improve' { $notice = "Usage: /improve <what you want me to change about myself>" }
                            default   { $notice = "unknown command: /$name  (try /help)" }
                        }
                    }
                }
                continue
            }

            # Ctrl+. opens shortcuts cheatsheet
            $isCtrlDot = (($key.Key -eq "OemPeriod") -or ($key.KeyChar -eq '.')) -and (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
            if ($isCtrlDot) {
                Show-ShortcutsHelp
                $script:NeedsFullClear = $true
                $script:NeedsFullPaint = $true
                continue
            }

            # ? with empty buffer opens cheatsheet
            if ($key.KeyChar -eq '?' -and [string]::IsNullOrEmpty($inputBuffer)) {
                Show-ShortcutsHelp
                $script:NeedsFullClear = $true
                $script:NeedsFullPaint = $true
                continue
            }

            if ($key.Key -eq "Escape") {
                if (Test-SlashMenuOpen -Buffer $inputBuffer) {
                    # Grok-like: dismiss dropdown, keep typed buffer
                    $script:SlashMenuDismissed = $true
                    $script:EscArmUntil = $null
                    $script:NeedsFullPaint = $true
                    continue
                }
                Clear-EscArmIfExpired
                if ($script:EscArmUntil) {
                    $running = $false
                } else {
                    $script:EscArmUntil = [datetime]::UtcNow.AddSeconds(2)
                    Set-Toast -Text "press esc again to quit" -Ms 2000
                }
            } elseif ($key.Key -eq "Tab") {
                $script:EscArmUntil = $null
                if (Test-SlashMenuOpen -Buffer $inputBuffer) {
                    $sm = @(Get-SlashMatches -Buffer $inputBuffer)
                    Sync-SlashSelection -Matches $sm
                    $inputBuffer = Get-SlashFill -Item $sm[$script:SlashSelIndex]
                    $script:SlashMenuDismissed = $true
                    $script:NeedsFullPaint = $true
                }
                continue
            } elseif ($key.Key -eq "Enter") {
                $script:EscArmUntil = $null
                $hasAlt = (($key.Modifiers -band [ConsoleModifiers]::Alt) -ne 0)
                # Alt+Enter => multiline newline (PS 5.1 may not always report Alt; also support trailing \)
                if ($hasAlt) {
                    $inputBuffer += "`n"
                    $script:InPromptHistory = $false
                    $script:NeedsFullPaint = $true
                    continue
                }
                if (Test-SlashMenuOpen -Buffer $inputBuffer) {
                    $sm = @(Get-SlashMatches -Buffer $inputBuffer)
                    Sync-SlashSelection -Matches $sm
                    $inputBuffer = Get-SlashFill -Item $sm[$script:SlashSelIndex]
                    $script:SlashMenuDismissed = $true
                }
                # Trailing backslash continues the line (PS 5.1-friendly multiline)
                if ($inputBuffer.Length -gt 0 -and $inputBuffer.EndsWith([string][char]92)) {
                    $inputBuffer = $inputBuffer.Substring(0, $inputBuffer.Length - 1) + "`n"
                    $script:InPromptHistory = $false
                    $script:NeedsFullPaint = $true
                    continue
                }
                $text = $inputBuffer.Trim()
                $inputBuffer = ""
                $script:InPromptHistory = $false
                $script:PromptHistoryIndex = -1
                if ([string]::IsNullOrWhiteSpace($text)) { continue }
                Add-PromptHistory -Line $text
                $script:NeedsFullPaint = $true

                if ($text.StartsWith("/")) {
                    $cmd = $text.Substring(1).Trim()
                    $parts = $cmd -split " ",2
                    $name = $parts[0].ToLower()
                    $arg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }

                    switch ($name) {
                        'help'    { $messages = @($messages) + [pscustomobject]@{ role='system'; content=(Get-HelpText) } }
                        'new'     { $messages = @(); Save-History -messages $messages -max 0; $notice = "new chat, Daddy" }
                        'clear'   { $messages = @(); Save-History -messages $messages -max 0; $notice = "history cleared, Daddy" }
                        'copy'    { $cr = Copy-LastAssistant -Messages $messages; $notice = $cr.Notice }
                        'export'  { $er = Export-Transcript -Messages $messages -PathArg $arg; $notice = $er.Notice }
                        'exit'    { $running = $false }
                        'theme'   {
                            if ($arg) {
                                if ($script:Themes.Contains($arg)) {
                                    $script:Config.theme = $arg; $script:CurrentTheme = $script:Themes[$arg]; Save-Config $script:Config
                                    $notice = "theme -> $arg"
                                } else { $notice = "unknown theme: $arg" }
                            } else {
                                $themeNames = @($script:Themes.Keys)
                                $currentIdx = [array]::IndexOf($themeNames, $script:Config.theme)
                                if ($currentIdx -lt 0) { $currentIdx = 0 }
                                $chosen = Select-Menu -Title "Select theme" -Options $themeNames -DefaultIndex $currentIdx
                                $script:NeedsFullClear = $true
                                $script:NeedsFullPaint = $true
                                if ($chosen) {
                                    $script:Config.theme = $chosen
                                    $script:CurrentTheme = $script:Themes[$chosen]
                                    Save-Config $script:Config
                                    $notice = "theme -> $chosen"
                                }
                            }
                        }
                        'config'  { $messages = @($messages) + [pscustomobject]@{ role='system'; content=(Get-ConfigText) } }
                        'improve' {
                            if (-not $arg) {
                                $notice = "Usage: /improve <what you want me to change about myself>"
                            } else {
                                $srcPath = Join-Path $script:ModuleRoot "Nautilus.psm1"
                                $source  = if (Test-Path $srcPath) { Get-Content -Raw $srcPath } else { "(source not found)" }
                                $context = $source.Substring(0, [Math]::Min(14000, $source.Length))

                                $improveMessages = @(
                                    [pscustomobject]@{ role = 'user'; content = "Current Nautilus.psm1 (excerpt):`n$context`n`n---`nDaddy's request: $arg" }
                                )
                                $contents    = Build-Contents -messages $improveMessages
                                $streamState = Invoke-GeminiStream -Contents $contents -Model $script:Config.model -Temperature 0.35 -SystemPrompt $script:ImproveSystemPrompt

                                $spinIdx = 0
                                $cancelled = $false
                                while (-not $streamState.Done) {
                                    if ($script:TuiForceExit) { $cancelled = $true; break }
                                    if ([Console]::KeyAvailable) {
                                        $ck = [Console]::ReadKey($true)
                                        if ($ck.Key -eq "Escape") { $cancelled = $true; break }
                                    }
                                    Render-Frame -messages $messages -inputBuffer "" -scrollOffset ([int]::MaxValue) `
                                                 -streamState $streamState -spinIdx $spinIdx `
                                                 -thinkingMsg "Reading my own code, Daddy..." -notice ""
                                    $spinIdx++
                                    Start-Sleep -Milliseconds 70
                                }

                                if ($cancelled) {
                                    Dispose-StreamState $streamState
                                    $streamState = $null
                                    $notice = "improve cancelled"
                                    if ($script:TuiForceExit) { $running = $false }
                                } else {
                                    $final = (Get-StreamFullText $streamState).Trim()
                                    if ($final) {
                                        $messages = @($messages) + [pscustomobject]@{ role='assistant'; content=$final }
                                    } else {
                                        $messages = @($messages) + [pscustomobject]@{ role='system'; content=(Format-ApiError $streamState.Error) }
                                    }
                                    Dispose-StreamState $streamState
                                    $streamState = $null
                                    Save-History -messages $messages -max $script:Config.maxHistory
                                }
                            }
                        }
                        'model'   {
                            if ($arg) {
                                $script:Config.model = $arg
                                Save-Config $script:Config
                                $notice = "model -> $arg"
                            } else {
                                $models = @(
                                    "gemini-3.8-flash"
                                    "gemini-3.7-flash"
                                    "gemini-3.6-flash"
                                    "gemini-3.5-flash"
                                    "gemini-3.5-flash-lite"
                                    "gemini-3.1-flash-lite"
                                    "gemini-2.5-flash"
                                )
                                $currentIdx = [array]::IndexOf($models, $script:Config.model)
                                if ($currentIdx -lt 0) { $currentIdx = 4 }
                                $chosen = Select-Menu -Title "Select model" -Options $models -DefaultIndex $currentIdx
                                $script:NeedsFullClear = $true
                                $script:NeedsFullPaint = $true
                                if ($chosen) {
                                    $script:Config.model = $chosen
                                    Save-Config $script:Config
                                    $notice = "model -> $chosen"
                                }
                            }
                        }
                        'search'  {
                            $cfg = Load-Config
                            $argLower = $arg.ToLower()
                            if ($argLower -eq 'on' -or $argLower -eq 'true' -or $argLower -eq '1') {
                                $cfg.enableSearch = $true
                                Save-Config $cfg
                                $script:Config = $cfg
                                $notice = "search grounding ON"
                            } elseif ($argLower -eq 'off' -or $argLower -eq 'false' -or $argLower -eq '0') {
                                $cfg.enableSearch = $false
                                Save-Config $cfg
                                $script:Config = $cfg
                                $notice = "search grounding OFF"
                            } else {
                                $state = if ($cfg.enableSearch) { "ON" } else { "OFF" }
                                $notice = "search grounding is currently $state  (use /search on|off)"
                            }
                        }
                        'update'  {
                            if ($script:PendingUpdateVersion) {
                                $applyUpdate = $true
                                $running = $false
                            } else {
                                # Force apply even if check has not finished / no newer version known
                                $applyUpdate = $true
                                $running = $false
                            }
                        }
                        default   { $notice = "unknown command: /$name  (try /help)" }
                    }
                    continue
                }

                # user message -> send to Gemini
                $messages = @($messages) + [pscustomobject]@{ role='user'; content=$text }
                Save-History -messages $messages -max $script:Config.maxHistory
                $scrollOffset = [int]::MaxValue   # jump to bottom on new message

                $contents = Build-Contents -messages $messages
                $streamState = Invoke-GeminiStream -Contents $contents -Model $script:Config.model -Temperature $script:Config.temperature -SystemPrompt $script:SystemPrompt

                $spinIdx = 0
                $thinkIdx = (Get-Random -Minimum 0 -Maximum $script:ThinkingLines.Count)
                $thinkTick = 0
                $started = $false
                $cancelled = $false
                while (-not $streamState.Done) {
                    if ($script:TuiForceExit) { $cancelled = $true; break }
                    if ([Console]::KeyAvailable) {
                        $ck = [Console]::ReadKey($true)
                        if ($ck.Key -eq "Escape") { $cancelled = $true; break }
                    }
                    $thinking = $script:ThinkingLines[$thinkIdx % $script:ThinkingLines.Count]
                    Render-Frame -messages $messages -inputBuffer "" -scrollOffset ([int]::MaxValue) -streamState $streamState -spinIdx $spinIdx -thinkingMsg $thinking -notice ""
                    $spinIdx++
                    $thinkTick++
                    if ($streamState.Chunks.Count -gt 0) { $started = $true }
                    elseif (($thinkTick % 8) -eq 0) { $thinkIdx++ }
                    Start-Sleep -Milliseconds 70
                }

                if ($cancelled) {
                    Dispose-StreamState $streamState
                    $streamState = $null
                    $notice = "request cancelled"
                    if ($script:TuiForceExit) { $running = $false }
                    continue
                }

                $fullStr = Get-StreamFullText $streamState
                if (-not $started -and [string]::IsNullOrEmpty($fullStr) -and $streamState.Error) {
                    Dispose-StreamState $streamState
                    $streamState = $null
                    $fbText, $fbErr = Invoke-GeminiFallback -Contents $contents -Model $script:Config.model -Temperature $script:Config.temperature -SystemPrompt $script:SystemPrompt
                    if ($fbText) {
                        $messages = @($messages) + [pscustomobject]@{ role='assistant'; content=$fbText }
                    } else {
                        $messages = @($messages) + [pscustomobject]@{ role='system'; content=(Format-ApiError $fbErr) }
                    }
                } else {
                    $finalText = $fullStr.Trim()
                    if ([string]::IsNullOrEmpty($finalText) -and $streamState.Error) {
                        $messages = @($messages) + [pscustomobject]@{ role='system'; content=(Format-ApiError $streamState.Error) }
                    } elseif ([string]::IsNullOrEmpty($finalText)) {
                        $messages = @($messages) + [pscustomobject]@{ role='system'; content="No response came back, Daddy. Try again." }
                    } else {
                        $messages = @($messages) + [pscustomobject]@{ role='assistant'; content=$finalText }
                    }
                    Dispose-StreamState $streamState
                    $streamState = $null
                }
                Save-History -messages $messages -max $script:Config.maxHistory
                continue
            } elseif ($key.Key -eq "Backspace") {
                $script:EscArmUntil = $null
                if ($inputBuffer.Length -gt 0) {
                    $inputBuffer = $inputBuffer.Substring(0, $inputBuffer.Length - 1)
                    $script:SlashMenuDismissed = $false
                    $script:InPromptHistory = $false
                    $script:NeedsFullPaint = $true
                }
            } elseif ($key.Key -eq "UpArrow") {
                $script:EscArmUntil = $null
                if (Test-SlashMenuOpen -Buffer $inputBuffer) {
                    $sm = @(Get-SlashMatches -Buffer $inputBuffer)
                    Sync-SlashSelection -Matches $sm
                    $script:SlashSelIndex = ($script:SlashSelIndex - 1 + $sm.Count) % $sm.Count
                    $script:NeedsFullPaint = $true
                } elseif ([string]::IsNullOrEmpty($inputBuffer) -or $script:InPromptHistory) {
                    if ($script:PromptHistory.Count -gt 0) {
                        if (-not $script:InPromptHistory) {
                            $script:PromptHistoryIndex = $script:PromptHistory.Count - 1
                            $script:InPromptHistory = $true
                        } elseif ($script:PromptHistoryIndex -gt 0) {
                            $script:PromptHistoryIndex--
                        }
                        $inputBuffer = $script:PromptHistory[$script:PromptHistoryIndex]
                        $script:NeedsFullPaint = $true
                    }
                } else {
                    $script:NeedsFullPaint = $true
                    if ($scrollOffset -eq [int]::MaxValue) {
                        $max = if ($script:LastMaxStart -ge 0) { $script:LastMaxStart } else { 0 }
                        $scrollOffset = [Math]::Max(0, $max - 1)
                    } else {
                        $scrollOffset = [Math]::Max(0, $scrollOffset - 1)
                    }
                }
            } elseif ($key.Key -eq "DownArrow") {
                $script:EscArmUntil = $null
                if (Test-SlashMenuOpen -Buffer $inputBuffer) {
                    $sm = @(Get-SlashMatches -Buffer $inputBuffer)
                    Sync-SlashSelection -Matches $sm
                    $script:SlashSelIndex = ($script:SlashSelIndex + 1) % $sm.Count
                    $script:NeedsFullPaint = $true
                } elseif ($script:InPromptHistory) {
                    if ($script:PromptHistoryIndex -lt ($script:PromptHistory.Count - 1)) {
                        $script:PromptHistoryIndex++
                        $inputBuffer = $script:PromptHistory[$script:PromptHistoryIndex]
                    } else {
                        $script:InPromptHistory = $false
                        $script:PromptHistoryIndex = -1
                        $inputBuffer = ""
                    }
                    $script:NeedsFullPaint = $true
                } elseif ($scrollOffset -eq [int]::MaxValue) {
                    # already pinned
                } else {
                    $script:NeedsFullPaint = $true
                    $max = if ($script:LastMaxStart -ge 0) { $script:LastMaxStart } else { 0 }
                    if ($scrollOffset -ge $max) {
                        $scrollOffset = [int]::MaxValue   # re-pin
                    } else {
                        $scrollOffset++
                    }
                }
            } elseif ($key.Key -eq "PageUp") {
                $script:EscArmUntil = $null
                $script:NeedsFullPaint = $true
                if ($scrollOffset -eq [int]::MaxValue) {
                    $max = if ($script:LastMaxStart -ge 0) { $script:LastMaxStart } else { 0 }
                    $scrollOffset = [Math]::Max(0, $max - 5)
                } else {
                    $scrollOffset = [Math]::Max(0, $scrollOffset - 5)
                }
            } elseif ($key.Key -eq "PageDown") {
                $script:EscArmUntil = $null
                $script:NeedsFullPaint = $true
                if ($scrollOffset -eq [int]::MaxValue) {
                    # already pinned
                } else {
                    $max = if ($script:LastMaxStart -ge 0) { $script:LastMaxStart } else { 0 }
                    $next = $scrollOffset + 5
                    if ($next -ge $max) {
                        $scrollOffset = [int]::MaxValue
                    } else {
                        $scrollOffset = $next
                    }
                }
            } elseif ($key.Key -eq "Home") {
                $script:EscArmUntil = $null
                $script:NeedsFullPaint = $true
                $scrollOffset = 0
            } elseif ($key.Key -eq "End") {
                $script:EscArmUntil = $null
                $script:NeedsFullPaint = $true
                $scrollOffset = [int]::MaxValue
            } else {
                $script:EscArmUntil = $null
                # Ctrl+J inserts newline (multiline)
                $isCtrlJ = ($key.Key -eq "J") -and (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
                if ($isCtrlJ -or ($key.KeyChar -eq [char]10)) {
                    $inputBuffer += "`n"
                    $script:InPromptHistory = $false
                    $script:NeedsFullPaint = $true
                    continue
                }
                $ch = $key.KeyChar
                if (-not [char]::IsControl($ch) -and $ch -ne [char]0) {
                    $inputBuffer += $ch
                    $script:SlashMenuDismissed = $false
                    $script:InPromptHistory = $false
                    $script:NeedsFullPaint = $true
                }
            }
        }
    } finally {
        try { if ($streamState) { Dispose-StreamState $streamState } } catch { }
        try { Stop-UpdateCheck } catch { }
        Exit-TUI
        Unregister-TuiCancelHandler
    }

    if ($applyUpdate) {
        Invoke-PendingUpdateApply
    }
}

# ===========================================================================
#  HELP / CONFIG TEXT
# ===========================================================================
function script:Get-HelpText {
    return @"
Nautilus commands (type / in the prompt for autocomplete):
  /help      Show this help
  /new       New chat (clear history + soft reset)
  /clear     Clear conversation history
  /copy      Copy last assistant reply (clipboard or ~/.nautilus/last-copy.txt)
  /export    Export transcript to ~/.nautilus/exports/ (optional path)
  /theme     List themes  |  /theme <name>  to switch
  /config    Show configuration
  /model     /model <name>  set the Gemini model
  /search    /search on|off  toggle Google Search grounding
  /improve   /improve <request>  ask me to improve my own code
  /update    Apply update from GitHub Pages (same as Ctrl+U when pending)
  /exit      Close Nautilus  (or double-Esc)

Keys:
  Enter      Send message (or run highlighted slash command)
  Alt+Enter  Insert newline (multiline); Ctrl+J same; or end a line with \ then Enter
  Esc        Dismiss slash menu; cancel stream; press again within ~2s to quit
  Tab        Fill slash command from autocomplete menu
  /          Open slash-command autocomplete dropdown
  ?          Open shortcuts cheatsheet (when prompt is empty)
  Ctrl+K     Command palette (slash actions)
  Ctrl+.     Open / close shortcuts cheatsheet
  Ctrl+U     Apply pending in-TUI update (when tip is shown)
  Up/Down    Prompt history when empty; slash menu when open; else scroll chat
  PgUp/PgDn  Page chat; Home/End jump
  Wheel      Scroll slash menu, chat, or pickers (best-effort mouse)
  Click      Select a slash/menu row (best-effort mouse)

Shell commands:
  nautilus                 Launch the interactive TUI
  nautilus ask "message"   One-shot question, print answer, exit
  nautilus config          Print / edit configuration
  nautilus theme           Switch theme
  nautilus clear           Clear history
  nautilus update          Self-update from GitHub Pages
  nautilus uninstall       Remove Nautilus
  nautilus help            Show this help
"@
}

function script:Get-ConfigText {
    $cfg = Load-Config
    $keyStatus = if ($cfg.apiKey) { "set (cached)" } else { "not set (proxy mode OK)" }
    $proxy = if ($cfg.proxyUrl) { $cfg.proxyUrl } else { "(direct Gemini)" }
    $search = if ($cfg.enableSearch) { "ON" } else { "OFF" }
    $gist = if ($cfg.keyUrl) { $cfg.keyUrl } elseif ($script:KeyGistUrl -notmatch '<GIST_ID>') { "(bundled gist)" } else { "not configured" }
    return @"
Nautilus configuration
  model       : $($cfg.model)
  theme       : $($cfg.theme)
  temperature : $($cfg.temperature)
  maxHistory  : $($cfg.maxHistory)
  search      : $search
  proxy       : $proxy
  api key     : $keyStatus
  gist source : $gist
  config file : $script:ConfigFile
  history     : $script:HistoryFile
  install     : $script:ModuleRoot

Edit by running: nautilus config edit
  Toggle search in TUI: /search on|off
"@
}

# ===========================================================================
#  ONE-SHOT ASK
# ===========================================================================
function script:Invoke-Ask {
    param([string]$message)
    $cfg = Load-Config
    $messages = @(
        [pscustomobject]@{ role='user'; content=$message }
    )
    $contents = Build-Contents -messages $messages
    $esc = $script:Esc
    Write-Host "$esc[38;5;117mDaddy$esc[0m $esc[38;5;240m>$esc[0m $message"
    $streamState = $null
    try {
        $streamState = Invoke-GeminiStream -Contents $contents -Model $cfg.model -Temperature $cfg.temperature -SystemPrompt $script:SystemPrompt
        $spin = 0
        $thinkIdx = Get-Random -Minimum 0 -Maximum $script:ThinkingLines.Count
        while (-not $streamState.Done) {
            $sp = $script:Spinner[$spin % $script:Spinner.Count]
            $msg = $script:ThinkingLines[$thinkIdx % $script:ThinkingLines.Count]
            Write-Host "`r$esc[38;5;81m$sp $msg$esc[0m$esc[K" -NoNewline
            $spin++
            if (($spin % 10) -eq 0) { $thinkIdx++ }
            Start-Sleep -Milliseconds 80
        }
        Write-Host "`r$esc[K" -NoNewline
        $full = (Get-StreamFullText $streamState).Trim()
        if (-not [string]::IsNullOrEmpty($full)) {
            Write-Host "$esc[38;5;81mNautilus$esc[0m $esc[38;5;240m>$esc[0m $full"
        } elseif ($streamState.Error) {
            Dispose-StreamState $streamState
            $streamState = $null
            $txt, $err = Invoke-GeminiFallback -Contents $contents -Model $cfg.model -Temperature $cfg.temperature -SystemPrompt $script:SystemPrompt
            if ($txt) { Write-Host "$esc[38;5;81mNautilus$esc[0m $esc[38;5;240m>$esc[0m $txt" }
            else { Write-Host "$esc[38;5;203mNautilus: $(Format-ApiError $err)$esc[0m" }
        } else {
            Write-Host "$esc[38;5;203mNautilus: No response came back, Daddy. Try again.$esc[0m"
        }
    } finally {
        if ($streamState) { Dispose-StreamState $streamState }
    }
}

# ===========================================================================
#  CONFIG EDITOR
# ===========================================================================
function script:Run-Config {
    param([string]$action)
    $cfg = Load-Config
    $esc = $script:Esc
    function Wc($t,$c){ "$esc[38;5;${c}m$t$esc[0m" }
    Write-Host ""
    Write-Host (Wc "  Nautilus configuration" 117)
    Write-Host (Wc "  ----------------------" 240)
    Write-Host (Wc "  model       : $($cfg.model)" 81)
    Write-Host (Wc "  theme       : $($cfg.theme)" 81)
    Write-Host (Wc "  temperature : $($cfg.temperature)" 81)
    Write-Host (Wc "  maxHistory  : $($cfg.maxHistory)" 81)
    $keyStatus = if ($cfg.apiKey) { "set (cached)" } else { "not set" }
    Write-Host (Wc "  api key     : $keyStatus" 81)
    Write-Host (Wc "  config file : $script:ConfigFile" 245)
    Write-Host (Wc "  history     : $script:HistoryFile" 245)
    Write-Host (Wc "  install     : $script:ModuleRoot" 245)
    Write-Host ""
    Write-Host (Wc "  Available themes: " 245 + (($script:Themes.Keys -join ", ")))
    Write-Host ""
    if ($action -eq "edit") {
        $newModel = Read-Host (Wc "  Set model (enter to keep [$($cfg.model)])" 240)
        if ($newModel) { $cfg.model = $newModel }
        $themes = ($script:Themes.Keys -join ",")
        $newTheme = Read-Host (Wc "  Set theme (enter to keep [$($cfg.theme)])  [$themes]" 240)
        if ($newTheme -and $script:Themes.Contains($newTheme)) { $cfg.theme = $newTheme }
        $newTemp = Read-Host (Wc "  Set temperature (enter to keep [$($cfg.temperature)])" 240)
        if ($newTemp) { try { $cfg.temperature = [double]$newTemp } catch {} }
        Write-Host (Wc "  Set keyUrl (gist raw URL, enter to keep)" 240)
        $newUrl = Read-Host
        if ($newUrl) { $cfg.keyUrl = $newUrl; $cfg.apiKey = "" }
        $pasteKey = Read-Host (Wc "  Or paste a key directly (enter to skip)" 240)
        if ($pasteKey) { $cfg.apiKey = $pasteKey.Trim() }
        Save-Config $cfg
        Write-Host ""
        Write-Host (Wc "  Saved, Daddy." 117)
        Write-Host ""
    }
}

# ===========================================================================
#  THEME SWITCHER (shell)
# ===========================================================================
function script:Run-Theme {
    param([string]$name)
    $cfg = Load-Config
    $esc = $script:Esc
    function Wc($t,$c){ "$esc[38;5;${c}m$t$esc[0m" }
    if ($name -and $script:Themes.Contains($name)) {
        $cfg.theme = $name
        Save-Config $cfg
        Write-Host (Wc "  Theme set to $name, Daddy." 81)
    } else {
        Write-Host ""
        Write-Host (Wc "  Available Nautilus themes:" 117)
        foreach ($k in $script:Themes.Keys) {
            $mark = if ($k -eq $cfg.theme) { "*" } else { " " }
            Write-Host (Wc "   $mark $k" 81)
        }
        Write-Host (Wc "  Switch with: nautilus theme <name>" 245)
        Write-Host ""
    }
}

# ===========================================================================
#  UPDATE / UNINSTALL
# ===========================================================================
function script:Run-Update {
    $esc = $script:Esc
    Write-Host "$esc[38;5;81m  Updating Nautilus from $script:RepoBase ...$esc[0m"
    $InstallRoot = $script:InstallRoot
    $RepoBase = $script:RepoBase
    # Nested Join-Path for Windows PowerShell 5.1 (no 3-arg Join-Path)
    $moduleDir = Join-Path $InstallRoot "Nautilus"
    if (-not (Test-Path -LiteralPath $moduleDir)) {
        New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch { }

    function script:Get-NautilusRemoteFile {
        param([string]$Uri, [string]$OutFile)
        $dir = Split-Path -Parent $OutFile
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $errs = @()
        $downloaded = $false

        # 1) Prefer native curl.exe / curl (never the Invoke-WebRequest alias)
        $curlPath = $null
        foreach ($candidate in @('curl.exe', 'curl', '/usr/bin/curl', '/bin/curl')) {
            $isPath = ($candidate.IndexOf([char]'/') -ge 0) -or ($candidate.IndexOf([char]'\') -ge 0)
            if ($isPath) {
                if (Test-Path -LiteralPath $candidate) { $curlPath = $candidate; break }
            } else {
                $c = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($c) { $curlPath = $c.Source; break }
            }
        }
        if ($curlPath) {
            try {
                $p = Start-Process -FilePath $curlPath -ArgumentList @('-fsSL','--retry','2','-o',$OutFile,'--',$Uri) -Wait -PassThru -NoNewWindow
                if ($p.ExitCode -eq 0 -and (Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
                    $downloaded = $true
                } else {
                    $errs += "curl exit=$($p.ExitCode)"
                }
            } catch {
                $errs += "curl: $($_.Exception.Message)"
            }
        } else {
            $errs += 'curl not found'
        }

        # 2) HttpClient
        if (-not $downloaded) {
            try {
                Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
                $client = New-Object System.Net.Http.HttpClient
                $client.Timeout = [TimeSpan]::FromSeconds(60)
                $resp = $client.GetAsync($Uri).GetAwaiter().GetResult()
                if ($resp.IsSuccessStatusCode) {
                    [System.IO.File]::WriteAllBytes($OutFile, $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult())
                    if ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
                        $downloaded = $true
                    } else {
                        $errs += 'HttpClient empty body'
                    }
                } else {
                    $errs += "HttpClient HTTP $([int]$resp.StatusCode)"
                }
                $client.Dispose()
            } catch {
                $errs += "HttpClient: $($_.Exception.Message)"
            }
        }

        # 3) Invoke-WebRequest on Windows
        if (-not $downloaded -and ($env:OS -eq 'Windows_NT')) {
            try {
                Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
                if ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
                    $downloaded = $true
                }
            } catch {
                $errs += "Invoke-WebRequest: $($_.Exception.Message)"
            }
        }

        if (-not $downloaded) {
            throw ("Failed to download {0} :: {1}" -f $Uri, ($errs -join ' | '))
        }
    }

    $okCount = 0
    foreach ($f in @("Nautilus.psd1", "Nautilus.psm1")) {
        $url = "$RepoBase/Nautilus/$f"
        $dest = Join-Path $moduleDir $f
        try {
            Get-NautilusRemoteFile -Uri $url -OutFile $dest
            if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
                Unblock-File -LiteralPath $dest -ErrorAction SilentlyContinue
            }
            Write-Host "$esc[38;5;245m  refreshed $f$esc[0m"
            $okCount++
        } catch {
            Write-Host "$esc[38;5;203m  failed to update $f : $($_.Exception.Message)$esc[0m"
        }
    }

    $newVer = $null
    if ($okCount -gt 0) {
        try {
            Import-Module (Join-Path $moduleDir "Nautilus.psd1") -Force -ErrorAction Stop
            $newVer = $script:NautilusVersion
        } catch {
            Write-Host "$esc[38;5;221m  downloaded, but reload failed: $($_.Exception.Message)$esc[0m"
            Write-Host "$esc[38;5;221m  Open a new PowerShell session to pick up the update.$esc[0m"
        }
    }
    if ($newVer) {
        Write-Host "$esc[38;5;117m  Nautilus updated to v$newVer, Daddy.$esc[0m"
    } elseif ($okCount -gt 0) {
        Write-Host "$esc[38;5;117m  Nautilus files refreshed. Restart PowerShell to load the new version, Daddy.$esc[0m"
    } else {
        Write-Host "$esc[38;5;203m  Update failed. Check your network and try again.$esc[0m"
    }
}

function script:Run-Uninstall {
    $esc = $script:Esc
    foreach ($p in @($PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost)) {
        if ($p -and (Test-Path $p)) {
            $content = Get-Content -Raw $p
            $cleaned = $content -replace "(?s)\s*# >>> Nautilus initialization >>>.*?# <<< Nautilus initialization <<<", ""
            if ($cleaned -ne $content) {
                Set-Content -Path $p -Value $cleaned.TrimEnd() -Encoding UTF8
                Write-Host "$esc[38;5;245m  cleaned profile: $p$esc[0m"
            }
        }
    }
    if (Test-Path $script:InstallRoot) {
        Remove-Item -Recurse -Force $script:InstallRoot -ErrorAction SilentlyContinue
        Write-Host "$esc[38;5;245m  removed $script:InstallRoot$esc[0m"
    }
    Write-Host "$esc[38;5;117m  Nautilus uninstalled. Farewell, Daddy.$esc[0m"
}

# ===========================================================================
#  PUBLIC COMMAND
# ===========================================================================
function nautilus {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $cmd = if ($Rest -and $Rest.Count -gt 0) { $Rest[0].ToLower() } else { "" }
    $rest = if ($Rest -and $Rest.Count -gt 1) { $Rest[1..($Rest.Count-1)] } else { @() }

    switch ($cmd) {
        ""          { Run-TUI }
        "chat"      { Run-TUI }
        "tui"       { Run-TUI }
        "ask"       {
            $msg = ($rest -join " ")
            if ([string]::IsNullOrWhiteSpace($msg)) {
                Write-Host "Usage: nautilus ask `"your message`""
                return
            }
            Invoke-Ask -message $msg
        }
        "config"    {
            $act = if ($rest -and $rest[0] -eq "edit") { "edit" } else { "view" }
            Run-Config -action $act
        }
        "theme"     {
            $tname = if ($rest) { $rest[0] } else { "" }
            Run-Theme -name $tname
        }
        "clear"     { Save-History -messages @() -max 0; Write-Host "History cleared, Daddy." }
        "update"    { Run-Update }
        "uninstall" { Run-Uninstall }
        "help"      {
            Write-Host ""
            Write-Host (Get-HelpText)
            Write-Host ""
        }
        default {
            Write-Host "Unknown command: $cmd"
            Write-Host "Run 'nautilus help' for usage."
        }
    }
}

try {
    Set-Alias -Name naut -Value nautilus -Scope Global -ErrorAction SilentlyContinue
} catch {
    try { Set-Alias -Name naut -Value nautilus -Scope Local -ErrorAction SilentlyContinue } catch { }
}
Export-ModuleMember -Function nautilus -Alias naut


