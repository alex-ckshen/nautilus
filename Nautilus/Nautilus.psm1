<#
    Nautilus - a pure-PowerShell futuristic TUI AI assistant.
    JARVIS-style personality, Gemini-powered, blue sci-fi aesthetic.
    Public command: nautilus  (alias: naut)
    Version: 0.3.43.0
#>

$script:NautilusVersion = "0.3.43.0"
$script:TuiActive = $false
$script:TuiForceExit = $false
$script:CancelHandlerRegistered = $false
$script:LastMaxStart = 0
$script:StatusIdx = 0

# ===========================================================================
#  PRIVATE CONFIG
# ===========================================================================
$script:NautilusHome    = Join-Path $HOME ".nautilus"
$script:ConfigFile      = Join-Path $script:NautilusHome "config.json"
$script:HistoryFile     = Join-Path $script:NautilusHome "history.json"
$script:RepoBase        = "https://alex-ckshen.github.io/nautilus"
$script:InstallRoot     = Join-Path $HOME ".nautilus"
$script:ModuleRoot      = Join-Path $script:InstallRoot "Nautilus"

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
    Nautilus = @{
        accent   = 81    # cyan
        deep     = 33    # blue
        bright   = 117   # light blue
        user     = 221   # warm yellow
        assistant= 81
        system   = 245   # grey
        dim      = 240
        border   = 60
        good     = 114
        warn     = 221
        error    = 203
        titlebar = 25
    }
    Midnight = @{
        accent   = 39
        deep     = 27
        bright   = 153
        user     = 222
        assistant= 39
        system   = 244
        dim      = 238
        border   = 24
        good     = 78
        warn     = 222
        error    = 203
        titlebar = 18
    }
    Cyber = @{
        accent   = 51
        deep     = 56
        bright   = 201
        user     = 213
        assistant= 51
        system   = 244
        dim      = 238
        border   = 91
        good     = 84
        warn     = 227
        error    = 207
        titlebar = 53
    }
    Abyss = @{
        accent   = 75
        deep     = 19
        bright   = 111
        user     = 180
        assistant= 75
        system   = 245
        dim      = 236
        border   = 24
        good     = 115
        warn     = 180
        error    = 174
        titlebar = 17
    }
}

# ===========================================================================
#  ANSI HELPERS
# ===========================================================================
$script:Esc = [char]27
function script:Get-C { param([string]$t, [int]$code) "$script:Esc[38;5;${code}m$t$script:Esc[0m" }
function script:Bold { param([string]$t, [int]$code) "$script:Esc[1;38;5;${code}m$t$script:Esc[0m" }
function script:Dim  { param([string]$t) "$script:Esc[2;38;5;240m$t$script:Esc[0m" }

# ===========================================================================
#  ARROW-KEY SELECT MENU  (Grok-Build style)
# ===========================================================================
function script:Select-Menu {
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$DefaultIndex = 0
    )
    if (-not $Options -or $Options.Count -eq 0) { return $null }

    $seen = @{}; $clean = @()
    foreach ($o in $Options) {
        if (-not $seen.ContainsKey($o)) { $seen[$o] = $true; $clean += $o }
    }
    $Options = $clean

    $idx = [Math]::Max(0, [Math]::Min($DefaultIndex, $Options.Count - 1))
    $th  = if ($script:CurrentTheme) { $script:CurrentTheme } else { $script:Themes["Midnight"] }
    $esc = $script:Esc
    $w   = [Console]::WindowWidth
    $h   = [Console]::WindowHeight

    $boxHeight = $Options.Count + 5
    $startRow  = [Math]::Max(2, [int](($h - $boxHeight) / 2))
    $startCol  = 4

    [Console]::CursorVisible = $false
    try {
        while ($true) {
            # Clear fixed region only (absolute coords — never stacks)
            for ($r = $startRow; $r -lt ($startRow + $boxHeight + 1); $r++) {
                Write-Host ("$esc[$r;1H" + (" " * [Math]::Max(0, $w - 1))) -NoNewline
            }

            $row = $startRow
            Write-Host ("$esc[$row;${startCol}H" + (Themed $Title 'bright')) -NoNewline
            $row++
            Write-Host ("$esc[$row;${startCol}H") -NoNewline
            $row++

            for ($i = 0; $i -lt $Options.Count; $i++) {
                if ($i -eq $idx) {
                    $line = (Themed "  > " 'accent') + (Bold $Options[$i] $th.accent)
                } else {
                    $line = (Themed "    $($Options[$i])" 'dim')
                }
                Write-Host ("$esc[$row;${startCol}H$line") -NoNewline
                $row++
            }

            $row++
            Write-Host ("$esc[$row;${startCol}H" + (Dim "Up/Down move   Enter select   Esc cancel")) -NoNewline

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow"   { $idx = ($idx - 1 + $Options.Count) % $Options.Count }
                "DownArrow" { $idx = ($idx + 1) % $Options.Count }
                "Enter"     { return $Options[$idx] }
                "Escape"    { return $null }
            }
        }
    }
    finally {
        for ($r = $startRow; $r -lt ($startRow + $boxHeight + 1); $r++) {
            Write-Host ("$esc[$r;1H" + (" " * [Math]::Max(0, $w - 1))) -NoNewline
        }
        [Console]::CursorVisible = $true
    }
}
function script:Themed {
    param([string]$t, [string]$role)
    $th = $script:CurrentTheme
    if (-not $th) { $th = $script:Themes["Midnight"] }
    if (-not $th) { return $t }
    $code = switch ($role) {
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
        default     { $th.accent }
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
            # Hard-break tokens longer than the wrap width
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
        enableSearch = $true
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
    if ($err -match 'timeout|timed out|作業逾時|Timeout') { return "Request timed out, Daddy. The model or the network took too long. Try again or switch to a lighter model." }
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
        $req = $null; $resp = $null; $reader = $null
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
                            [System.Threading.Monitor]::Enter($state.Full)
                            try { [void]$state.Full.Append($p.text) }
                            finally { [System.Threading.Monitor]::Exit($state.Full) }
                            $state.Chunks.Enqueue($p.text)
                        }
                    }
                }
            }
        } catch {
            $state.Error = $_.Exception.Message
        } finally {
            try { if ($reader) { $reader.Close() } } catch { }
            try { if ($resp) { $resp.Close() } } catch { }
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
    try {
        [System.Threading.Monitor]::Enter($state.Full)
        try { return $state.Full.ToString() }
        finally { [System.Threading.Monitor]::Exit($state.Full) }
    } catch {
        try { return $state.Full.ToString() } catch { return "" }
    }
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
$script:Spinner = @("⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏")
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
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        try {
            $sig = @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
'@
            $type = Add-Type -MemberDefinition $sig -Name 'NautilusCon' -Namespace 'Nautilus' -PassThru -ErrorAction Stop
            $h = $type::GetStdHandle(-11)
            $mode = 0
            [void]$type::GetConsoleMode($h, [ref]$mode)
            [void]$type::SetConsoleMode($h, $mode -bor 0x0004)
        } catch { }
    }
    try { Set-ItemProperty "HKCU:\Console" "VirtualTerminalLevel" -Type DWord 1 -ErrorAction SilentlyContinue } catch { }
}

function script:Enter-TUI {
    [Console]::CursorVisible = $false
    Write-Host "$script:Esc[?1049h" -NoNewline   # alternate screen
    Write-Host "$script:Esc[?25l" -NoNewline     # hide cursor
    Write-Host "$script:Esc[2J" -NoNewline       # clear
    $script:TuiActive = $true
}
function script:Exit-TUI {
    if (-not $script:TuiActive) {
        # Still best-effort restore in case of partial entry
    }
    try {
        Write-Host "$script:Esc[?1049l" -NoNewline  # leave alternate screen
        Write-Host "$script:Esc[?25h" -NoNewline    # show cursor
        Write-Host "$script:Esc[0m" -NoNewline      # reset attrs
    } catch { }
    try { [Console]::CursorVisible = $true } catch { }
    $script:TuiActive = $false
}

function script:Register-TuiCancelHandler {
    # Restore alternate screen on Ctrl+C. Safe to call multiple times.
    # Inline ANSI here: event handlers may not resolve module script: functions.
    if ($script:CancelHandlerRegistered) { return }
    try {
        $script:CancelHandler = [ConsoleCancelEventHandler]{
            param($sender, $e)
            $e.Cancel = $true
            try {
                $esc = [char]27
                [Console]::Write("$esc[?1049l$esc[?25h$esc[0m")
                [Console]::CursorVisible = $true
            } catch { }
            $script:TuiActive = $false
            $script:TuiForceExit = $true
        }
        [Console]::add_CancelKeyPress($script:CancelHandler)
        $script:CancelHandlerRegistered = $true
    } catch {
        # Some hosts (ISE, remoting) have no CancelKeyPress — try/finally still covers most exits
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

function script:Clear-Screen {
    Write-Host "$script:Esc[H$script:Esc[2J" -NoNewline
}

function script:Write-At {
    param([int]$row, [int]$col, [string]$text, [switch]$ClearEol)
    if ($null -eq $text) { $text = "" }
    $suffix = if ($ClearEol) { "$script:Esc[K" } else { "" }
    Write-Host "$script:Esc[$($row);$($col)H$text$suffix" -NoNewline
}

function script:Clear-Row {
    param([int]$row, [int]$width)
    $w = [Math]::Max(0, $width)
    Write-Host ("$script:Esc[$row;1H" + (" " * $w) + "$script:Esc[$row;1H") -NoNewline
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
    $th = $script:CurrentTheme
    if (-not $th) { $th = $script:Themes["Nautilus"] }
    $w = [Console]::WindowWidth
    $h = [Console]::WindowHeight
    if ($w -lt 30 -or $h -lt 12) {
        Clear-Screen
        Write-At 1 1 (Themed "Nautilus needs a larger terminal window." 'error') -ClearEol
        return
    }

    # Layout (1-based rows):
    #   1          title bar
    #   2          top border
    #   3..h-3     chat viewport
    #   h-2        bottom border
    #   h-1        status
    #   h          input
    $chatTop    = 3
    $chatBottom = $h - 3
    $chatHeight = [Math]::Max(1, $chatBottom - $chatTop + 1)
    $chatWidth  = [Math]::Max(10, $w - 2)
    $statusRow  = $h - 1
    $inputRow   = $h
    $borderRowT = 2
    $borderRowB = $h - 2

    $titleBar = "  N A U T I L U S  v$($script:NautilusVersion)  "
    $conn = "  $([char]0x25C9) connected  asia-01  "
    $modelName = if ($script:Config -and $script:Config.model) { $script:Config.model } else { $script:DefaultModel }
    $modelTag = "model: $modelName  "
    $padConn = $w - $titleBar.Length - $conn.Length - $modelTag.Length
    if ($padConn -lt 0) { $padConn = 0 }
    $topLine = (Themed $titleBar 'bright') + (Themed (" " * $padConn) 'titlebar') + (Themed $conn 'accent') + (Themed $modelTag 'dim')

    $borderTop = (Themed ([string]([char]0x2550) * [Math]::Max(1, $w - 1)) 'border')
    $borderBot = $borderTop

    # Build rendered lines for the chat area
    $lines = New-Object System.Collections.Generic.List[object]
    if ($null -eq $messages) { $messages = @() }
    foreach ($m in $messages) {
        $label = switch ($m.role) {
            'user'      { "Daddy" }
            'assistant' { "Nautilus" }
            default     { "System" }
        }
        $roleName = switch ($m.role) {
            'user'      { 'user' }
            'assistant' { 'assistant' }
            default     { 'system' }
        }
        $roleCode = switch ($m.role) {
            'user'      { $th.user }
            'assistant' { $th.assistant }
            default     { $th.system }
        }
        $prefix = (Bold "$label " $roleCode) + (Themed ([string]([char]0x203A) + " ") $roleName)
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

    # In-progress streaming message
    if ($streamState -and -not $streamState.Done) {
        $prefix = (Bold "Nautilus " $th.assistant) + (Themed ([string]([char]0x203A) + " ") 'assistant')
        $prefixLen = [Math]::Max(2, (VisibleLen $prefix))
        $partial = Get-StreamFullText $streamState
        if ([string]::IsNullOrEmpty($partial)) {
            $sp = $script:Spinner[$spinIdx % $script:Spinner.Count]
            $msg = if ($thinkingMsg) { $thinkingMsg } else { "thinking..." }
            $lines.Add(@{ text = $prefix + (Themed "$sp $msg" 'assistant'); role = "assistant" })
        } else {
            $wrapped = Wrap-Text -text $partial -width ($chatWidth - $prefixLen)
            $first = $true
            foreach ($wl in $wrapped) {
                if ($first) {
                    $lines.Add(@{ text = $prefix + (Themed $wl 'assistant'); role = "assistant" })
                    $first = $false
                } else {
                    $lines.Add(@{ text = (" " * $prefixLen) + (Themed $wl 'assistant'); role = "assistant" })
                }
            }
            $sp = $script:Spinner[$spinIdx % $script:Spinner.Count]
            $lines.Add(@{ text = (" " * $prefixLen) + (Themed "$sp" 'dim'); role = "assistant" })
        }
    } elseif ($streamState -and $streamState.Done) {
        $fullStr = Get-StreamFullText $streamState
        if (-not [string]::IsNullOrEmpty($streamState.Error) -and [string]::IsNullOrEmpty($fullStr)) {
            $prefix = (Bold "Nautilus " $th.assistant) + (Themed ([string]([char]0x203A) + " ") 'assistant')
            $lines.Add(@{ text = $prefix + (Themed (Format-ApiError $streamState.Error) 'error'); role = "assistant" })
        }
    }

    # Empty state: home screen
    if ((@($messages).Count -eq 0) -and -not $streamState) {
        $lines.Clear()
        $lines.Add(@{ text = ""; role = "gap" })
        $lines.Add(@{ text = (Themed "  Daddy, welcome back." 'bright'); role = "assistant" })
        $lines.Add(@{ text = ""; role = "gap" })
        $lines.Add(@{ text = (Themed "  All systems online. Awaiting your orders, Daddy." 'assistant'); role = "assistant" })
        $lines.Add(@{ text = ""; role = "gap" })
        $lines.Add(@{ text = (Dim "  Suggested commands:"); role = "system" })
        $lines.Add(@{ text = (Themed "  /help" 'accent') + (Dim "   - list commands and slash-actions"); role = "system" })
        $lines.Add(@{ text = (Themed "  /theme" 'accent') + (Dim "  - switch the colour theme"); role = "system" })
        $lines.Add(@{ text = (Themed "  /config" 'accent') + (Dim " - view / edit configuration"); role = "system" })
        $lines.Add(@{ text = (Themed "  /clear" 'accent') + (Dim "  - wipe conversation history"); role = "system" })
        $lines.Add(@{ text = (Themed "  /exit" 'accent') + (Dim "   - close Nautilus  (or press Esc)"); role = "system" })
        $lines.Add(@{ text = ""; role = "gap" })
        $lines.Add(@{ text = (Dim "  Or just start typing, Daddy."); role = "system" })
    }

    # ---- Paint (home + clear-eol; avoid full 2J flicker) ----
    Write-Host "$script:Esc[H" -NoNewline
    Write-At 1 1 $topLine -ClearEol
    Write-At $borderRowT 1 $borderTop -ClearEol

    $total = $lines.Count
    $maxStart = [Math]::Max(0, $total - $chatHeight)
    $script:LastMaxStart = $maxStart
    if ($scrollOffset -ge [int]::MaxValue -or $scrollOffset -lt 0) {
        $start = $maxStart   # pin to bottom
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
    # Clear any leftover rows in the chat viewport
    while ($r -le $chatBottom) {
        Write-At $r 1 "" -ClearEol
        $r++
    }

    Write-At $borderRowB 1 $borderBot -ClearEol

    # status line (rotating flavour when idle; notice overrides)
    $themeName = if ($script:Config -and $script:Config.theme) { $script:Config.theme } else { "Nautilus" }
    if ($notice) {
        $statusText = (Themed $notice 'warn')
    } elseif ($streamState -and -not $streamState.Done) {
        $sp = $script:Spinner[$spinIdx % $script:Spinner.Count]
        $msg = if ($thinkingMsg) { $thinkingMsg } else { "working..." }
        $statusText = (Themed "$sp $msg" 'accent')
    } else {
        $flavour = $script:StatusLines[$script:StatusIdx % $script:StatusLines.Count]
        $statusText = (Themed ([string]([char]0x25C9)) 'good') + (Themed " online" 'dim') + (Themed "  |  $themeName" 'dim') + (Themed "  |  $flavour" 'dim')
    }
    # Truncate status to width
    if ((VisibleLen $statusText) -gt ($w - 1)) {
        # keep it simple: rely on ClearEol; oversize ANSI is rare
    }
    Write-At $statusRow 1 $statusText -ClearEol

    # input line — always clear EOL so shortening the buffer leaves no ghosts
    $prompt = (Themed ([string]([char]0x25B6) + " ") 'accent')
    $buf = if ($null -eq $inputBuffer) { "" } else { $inputBuffer }
    $maxBuf = [Math]::Max(1, $w - 4)
    if ($buf.Length -gt $maxBuf) { $buf = $buf.Substring($buf.Length - $maxBuf) }
    Write-At $inputRow 1 ("$prompt$buf") -ClearEol
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

    # Ensure alternate screen is restored even on Ctrl+C / terminating errors
    trap {
        try { Exit-TUI } catch { }
        break
    }

    Register-TuiCancelHandler
    try {
        Enter-TUI
        Show-Startup
        $inputBuffer = ""
        $notice = ""
        $spinIdx = 0
        $thinkIdx = 0
        $scrollOffset = [int]::MaxValue   # pin-to-bottom sentinel
        $running = $true
        $idleTicks = 0

        while ($running) {
            if ($script:TuiForceExit) { $running = $false; break }

            # Rotate flavour status every few idle frames
            $idleTicks++
            if ($idleTicks -ge 1) {
                # StatusIdx advances when we re-render after key; bump occasionally via key wait is fine
            }
            Render-Frame -messages $messages -inputBuffer $inputBuffer -scrollOffset $scrollOffset -streamState $null -spinIdx $spinIdx -thinkingMsg "" -notice $notice
            $notice = ""

            $waitTicks = 0
            $keyReady = $false
            while (-not $keyReady) {
                if ($script:TuiForceExit) { break }
                try { $keyReady = [Console]::KeyAvailable } catch { $keyReady = $true }
                if ($keyReady) { break }
                Start-Sleep -Milliseconds 50
                $waitTicks++
                # Re-paint every ~1.2s so status flavour lines rotate while idle
                if ($waitTicks -ge 24) {
                    $waitTicks = 0
                    $script:StatusIdx = ($script:StatusIdx + 1) % [Math]::Max(1, $script:StatusLines.Count)
                    Render-Frame -messages $messages -inputBuffer $inputBuffer -scrollOffset $scrollOffset -streamState $null -spinIdx $spinIdx -thinkingMsg "" -notice ""
                }
            }
            if ($script:TuiForceExit) { $running = $false; break }

            $key = [Console]::ReadKey($true)

            if ($key.Key -eq "Escape") {
                $running = $false
            } elseif ($key.Key -eq "Enter") {
                $text = $inputBuffer.Trim()
                $inputBuffer = ""
                if ([string]::IsNullOrWhiteSpace($text)) { continue }

                if ($text.StartsWith("/")) {
                    $cmd = $text.Substring(1).Trim()
                    $parts = $cmd -split " ",2
                    $name = $parts[0].ToLower()
                    $arg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }

                    switch ($name) {
                        'help'    { $messages = @($messages) + [pscustomobject]@{ role='system'; content=(Get-HelpText) } }
                        'clear'   { $messages = @(); Save-History -messages $messages -max 0; $notice = "history cleared, Daddy" }
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
                    # Allow Esc to cancel in-flight request
                    if ([Console]::KeyAvailable) {
                        $ck = [Console]::ReadKey($true)
                        if ($ck.Key -eq "Escape") { $cancelled = $true; break }
                    }
                    $thinking = $script:ThinkingLines[$thinkIdx % $script:ThinkingLines.Count]
                    Render-Frame -messages $messages -inputBuffer "" -scrollOffset ([int]::MaxValue) -streamState $streamState -spinIdx $spinIdx -thinkingMsg $thinking -notice ""
                    $spinIdx++
                    $thinkTick++
                    if ($streamState.Chunks.Count -gt 0) {
                        $started = $true
                    } elseif (($thinkTick % 8) -eq 0) {
                        $thinkIdx++
                    }
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
                    # streaming failed entirely -> non-streaming fallback
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
                if ($inputBuffer.Length -gt 0) {
                    $inputBuffer = $inputBuffer.Substring(0, $inputBuffer.Length - 1)
                }
            } elseif ($key.Key -eq "UpArrow") {
                # Leave pin-to-bottom and move up one line
                if ($scrollOffset -eq [int]::MaxValue) {
                    $max = if ($script:LastMaxStart -ge 0) { $script:LastMaxStart } else { 0 }
                    $scrollOffset = [Math]::Max(0, $max - 1)
                } else {
                    $scrollOffset = [Math]::Max(0, $scrollOffset - 1)
                }
            } elseif ($key.Key -eq "DownArrow") {
                if ($scrollOffset -eq [int]::MaxValue) {
                    # already pinned
                } else {
                    $max = if ($script:LastMaxStart -ge 0) { $script:LastMaxStart } else { 0 }
                    if ($scrollOffset -ge $max) {
                        $scrollOffset = [int]::MaxValue   # re-pin
                    } else {
                        $scrollOffset++
                    }
                }
            } elseif ($key.Key -eq "PageUp") {
                if ($scrollOffset -eq [int]::MaxValue) {
                    $max = if ($script:LastMaxStart -ge 0) { $script:LastMaxStart } else { 0 }
                    $scrollOffset = [Math]::Max(0, $max - 5)
                } else {
                    $scrollOffset = [Math]::Max(0, $scrollOffset - 5)
                }
            } elseif ($key.Key -eq "PageDown") {
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
                $scrollOffset = 0
            } elseif ($key.Key -eq "End") {
                $scrollOffset = [int]::MaxValue
            } else {
                $ch = $key.KeyChar
                if (-not [char]::IsControl($ch) -and $ch -ne [char]0) {
                    $inputBuffer += $ch
                }
            }
        }
    } finally {
        try { if ($streamState) { Dispose-StreamState $streamState } } catch { }
        Exit-TUI
        Unregister-TuiCancelHandler
    }
}

# ===========================================================================
#  HELP / CONFIG TEXT
# ===========================================================================
function script:Get-HelpText {
    return @"
Nautilus commands (type in the prompt):
  /help      Show this help
  /clear     Clear conversation history
  /theme     List themes  |  /theme <name>  to switch
  /config    Show configuration
  /model     /model <name>  set the Gemini model
  /search    /search on|off  toggle Google Search grounding
  /improve   /improve <request>  ask me to improve my own code
  /exit      Close Nautilus  (or press Esc)

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
            $line = "$esc[38;5;81m$sp $msg$esc[0m"
            Write-Host "`r$line$esc[K" -NoNewline
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
    $searchState = if ($cfg.enableSearch) { "ON" } else { "OFF" }
    Write-Host (Wc "  search      : $searchState" 81)
    $proxyShow = if ($cfg.proxyUrl) { $cfg.proxyUrl } else { "(none)" }
    Write-Host (Wc "  proxy       : $proxyShow" 81)
    $keyStatus = if ($cfg.apiKey) { "set (cached)" } else { "not set (proxy mode OK)" }
    Write-Host (Wc "  api key     : $keyStatus" 81)
    Write-Host (Wc "  config file : $script:ConfigFile" 245)
    Write-Host (Wc "  history     : $script:HistoryFile" 245)
    Write-Host (Wc "  install     : $script:ModuleRoot" 245)
    Write-Host ""
    Write-Host ((Wc "  Available themes: " 245) + (Wc ($script:Themes.Keys -join ", ") 81))
    Write-Host ""
    if ($action -eq "edit") {
        $newModel = Read-Host (Wc "  Set model (enter to keep [$($cfg.model)])" 240)
        if ($newModel) { $cfg.model = $newModel }
        $themes = ($script:Themes.Keys -join ",")
        $newTheme = Read-Host (Wc "  Set theme (enter to keep [$($cfg.theme)])  [$themes]" 240)
        if ($newTheme -and $script:Themes.Contains($newTheme)) { $cfg.theme = $newTheme }
        $newTemp = Read-Host (Wc "  Set temperature (enter to keep [$($cfg.temperature)])" 240)
        if ($newTemp) { try { $cfg.temperature = [double]$newTemp } catch {} }
        $searchCur = if ($cfg.enableSearch) { "on" } else { "off" }
        $newSearch = Read-Host (Wc "  Search grounding on/off (enter to keep [$searchCur])" 240)
        if ($newSearch) {
            $ns = $newSearch.Trim().ToLower()
            if ($ns -in @('on','true','1','yes')) { $cfg.enableSearch = $true }
            elseif ($ns -in @('off','false','0','no')) { $cfg.enableSearch = $false }
        }
        Write-Host (Wc "  Set keyUrl (gist raw URL, enter to keep)" 240)
        $newUrl = Read-Host
        if ($newUrl) { $cfg.keyUrl = $newUrl; $cfg.apiKey = "" }
        $pasteKey = Read-Host (Wc "  Or paste a key directly (enter to skip)" 240)
        if ($pasteKey) { $cfg.apiKey = $pasteKey.Trim() }
        Save-Config $cfg
        $script:Config = $cfg
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
    $moduleDir = Join-Path $InstallRoot "Nautilus"
    if (-not (Test-Path $moduleDir)) {
        New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch { }
    foreach ($f in @("Nautilus.psd1", "Nautilus.psm1")) {
        $url = "$RepoBase/Nautilus/$f"
        $dest = Join-Path $moduleDir $f
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
            if (Get-Command Unblock-File -ErrorAction SilentlyContinue) { Unblock-File $dest }
            Write-Host "$esc[38;5;245m  refreshed $f$esc[0m"
        } catch {
            Write-Host "$esc[38;5;203m  failed to update $f : $($_.Exception.Message)$esc[0m"
        }
    }
    try {
        Import-Module (Join-Path $moduleDir "Nautilus.psd1") -Force -ErrorAction Stop
    } catch { }
    Write-Host "$esc[38;5;117m  Nautilus is up to date, Daddy.$esc[0m"
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

Set-Alias -Name naut -Value nautilus -Scope Global
Export-ModuleMember -Function nautilus -Alias naut
