<#
    Nautilus - pure-PowerShell TUI AI assistant.
    Installer: downloads the module to ~/.nautilus and registers the `nautilus`
    command in the current user's PowerShell profile so it is available in every
    new session. Idempotent and safe to re-run (also serves as the update path).

    Usage:
        irm https://alex-ckshen.github.io/nautilus/install.ps1 | iex
#>

[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $HOME ".nautilus"),
    [string]$RepoBase    = "https://alex-ckshen.github.io/nautilus",
    [switch]$Uninstall,
    [switch]$Silent
)

# --- Blue sci-fi ANSI helpers (work on PS 5.1 + PS 7) -------------------------
$esc = [char]27
function script:W-C { param($t) "$esc[38;5;81m$t$esc[0m" }   # cyan
function script:W-D { param($t) "$esc[38;5;33m$t$esc[0m" }   # blue
function script:W-B { param($t) "$esc[1;38;5;117m$t$esc[0m" } # bright light blue bold
function script:W-G { param($t) "$esc[38;5;245m$t$esc[0m" }   # grey
function script:W-Y { param($t) "$esc[38;5;221m$t$esc[0m" }   # warm yellow
function script:W-R { param($t) "$esc[38;5;203m$t$esc[0m" }   # soft red
function script:W-Logo {
    # Avoid ASCII-art pipes and nested quotes: Windows PS 5.1 irm|iex misparses them as pipelines.
    Write-Host (W-B '  N A U T I L U S')
    Write-Host (W-G '  pure-PowerShell TUI AI assistant')
}

# --- TLS 1.2 for Windows PowerShell 5.1 ----------------------------------------
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch { }

$ErrorActionPreference = "Stop"

function script:Remove-ProfileBlock {
    param([string]$ProfilePath)
    if (-not (Test-Path $ProfilePath)) { return }
    $content = Get-Content -Raw $ProfilePath
    $start = "    # >>> Nautilus initialization >>>"
    $end   = "    # <<< Nautilus initialization <<<"
    $pattern = "(?s)\s*# >>> Nautilus initialization >>>.*?# <<< Nautilus initialization <<<"
    if ($content -match $pattern) {
        $cleaned = $content -replace $pattern, ""
        Set-Content -Path $ProfilePath -Value $cleaned.TrimEnd() -NoNewline:$false -Encoding UTF8
        Write-Host (W-G "  removed profile hook from $ProfilePath")
    }
}

function script:Add-ProfileBlock {
    param([string]$ProfilePath)
    $dir = Split-Path -Parent $ProfilePath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $block = @"

# >>> Nautilus initialization >>>
$__nautManifest = Join-Path (Join-Path $InstallRoot "Nautilus") "Nautilus.psd1"
if (Test-Path $__nautManifest) {
    Import-Module $__nautManifest -Force -ErrorAction SilentlyContinue
}
# <<< Nautilus initialization <<<
"@
    if (-not (Test-Path $ProfilePath)) {
        Set-Content -Path $ProfilePath -Value $block.Trim() -Encoding UTF8
        Write-Host (W-G "  created profile at $ProfilePath")
    } else {
        $content = Get-Content -Raw $ProfilePath
        if ($content -match "(?s)# >>> Nautilus initialization >>>.*?# <<< Nautilus initialization <<<") {
            Write-Host (W-G "  profile hook already present at $ProfilePath")
        } else {
            Add-Content -Path $ProfilePath -Value $block -Encoding UTF8
            Write-Host (W-G "  added profile hook to $ProfilePath")
        }
    }
}

Write-Host ""
W-Logo
Write-Host ""
Write-Host (W-D "  Initializing Nautilus installer...")
Write-Host ""

if ($Uninstall) {
    Write-Host (W-Y "  Uninstalling Nautilus...")
    foreach ($p in @($PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost)) {
        if ($p) { Remove-ProfileBlock -ProfilePath $p }
    }
    if (Test-Path $InstallRoot) {
        Remove-Item -Recurse -Force $InstallRoot -ErrorAction SilentlyContinue
        Write-Host (W-G "  removed $InstallRoot")
    }
    Write-Host ""
    Write-Host (W-B "  Nautilus uninstalled. Farewell, Daddy.")
    Write-Host ""
    return
}

# --- Ensure install location -------------------------------------------------
if (-not (Test-Path $InstallRoot)) {
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
}
$ModuleRoot = Join-Path $InstallRoot "Nautilus"
if (-not (Test-Path $ModuleRoot)) {
    New-Item -ItemType Directory -Path $ModuleRoot -Force | Out-Null
}

Write-Host (W-D "  Target: $ModuleRoot")
Write-Host (W-C "  Establishing secure link to _alex.shen repository (asia-01)...")



function script:Get-RemoteFile {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch { }

    $errs = @()

    # 1) Native curl only (Application). Never use the curl alias.
    $curlPath = $null
    foreach ($candidate in @('curl.exe', 'curl', '/usr/bin/curl', '/bin/curl')) {
        if (($candidate.IndexOf([char]'/') -ge 0) -or ($candidate.IndexOf([char]'\') -ge 0)) {
            if (Test-Path -LiteralPath $candidate) { $curlPath = $candidate; break }
        } else {
            $cmd = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($cmd) { $curlPath = $cmd.Source; break }
        }
    }
    if ($curlPath) {
        $p = Start-Process -FilePath $curlPath -ArgumentList @('-fsSL','--retry','2','-o',$OutFile,'--',$Uri) -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -eq 0 -and (Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
            return
        }
        $errs += "curl exit=$($p.ExitCode)"
    } else {
        $errs += 'curl not found'
    }

    # 2) HttpClient
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        $handler = New-Object System.Net.Http.HttpClientHandler
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(60)
        $task = $client.GetAsync($Uri)
        $resp = $task.GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode)" }
        $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        [System.IO.File]::WriteAllBytes($OutFile, $bytes)
        $client.Dispose()
        if ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
            return
        }
        $errs += 'HttpClient empty body'
    } catch {
        $errs += "HttpClient: $($_.Exception.Message)"
    }

    # 3) Invoke-WebRequest only on Windows
    if ($env:OS -eq 'Windows_NT' -or ((Get-Variable IsWindows -ErrorAction SilentlyContinue) -and $IsWindows)) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
            if ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
                return
            }
        } catch {
            $errs += "Invoke-WebRequest: $($_.Exception.Message)"
        }
    }

    throw ("Download failed for {0} :: {1}" -f $Uri, ($errs -join ' | '))
}

# --- Download module files ---------------------------------------------------
$files = @("Nautilus.psd1", "Nautilus.psm1")
foreach ($f in $files) {
    $url  = "$RepoBase/Nautilus/$f"
    $dest = Join-Path $ModuleRoot $f
    try {
        Get-RemoteFile -Uri $url -OutFile $dest
        if (Get-Command Unblock-File -ErrorAction SilentlyContinue) { Unblock-File $dest }
        Write-Host (W-G "  downloaded $f")
    } catch {
        Write-Host (W-R "  failed to download $f from $url")
        Write-Host (W-R "  Error: $($_.Exception.Message)")
        Write-Host ""
        Write-Host (W-Y "  Tip: GitHub Pages can take a minute to publish after enabling.")
        Write-Host (W-Y "  Re-run the install command in a moment.")
        exit 1
    }
}

# --- Register in profile (CurrentUserAllHosts so it works everywhere) ---------
$targetProfile = $PROFILE.CurrentUserAllHosts
if (-not $targetProfile) { $targetProfile = Join-Path (Split-Path $PROFILE) "profile.ps1" }
Add-ProfileBlock -ProfilePath $targetProfile

# --- Load into the current session immediately --------------------------------
$script:NautilusImportOk = $false
try {
    Import-Module (Join-Path $ModuleRoot "Nautilus.psd1") -Force -ErrorAction Stop
    if (Get-Command nautilus -ErrorAction SilentlyContinue) {
        $script:NautilusImportOk = $true
        Write-Host (W-G "  module loaded in current session")
    } else {
        Write-Host (W-Y "  module file installed, but 'nautilus' is not yet on PATH in this session")
        Write-Host (W-Y "  open a new PowerShell window, then run: nautilus")
    }
} catch {
    Write-Host (W-R "  failed to load module in this session:")
    Write-Host (W-R "  $($_.Exception.Message)")
    Write-Host (W-Y "  Files are installed. Open a NEW PowerShell window and run: nautilus")
}

Write-Host ""
Write-Host (W-B "  +----------------------------------------------------------+")
Write-Host (W-B "     Nautilus core online - personality matrix loaded")
Write-Host (W-B "     Welcome back, Daddy. Systems are nominal.")
Write-Host (W-B "  +----------------------------------------------------------+")
Write-Host ""
Write-Host (W-C "  Quick start:")
Write-Host (W-G "    nautilus                 - launch the interactive TUI")
Write-Host (W-G "    nautilus ask `"hello`"     - one-shot question")
Write-Host (W-G "    nautilus help            - show all commands")
Write-Host (W-G "    nautilus config          - view / edit configuration")
Write-Host (W-G "    nautilus theme           - switch theme")
Write-Host (W-G "    nautilus update         - self-update")
Write-Host (W-G "    nautilus uninstall      - remove Nautilus")
Write-Host ""
if (-not $Silent) {
    if ($script:NautilusImportOk -and (Get-Command nautilus -ErrorAction SilentlyContinue)) {
        Write-Host (W-D "  Launch now? [Y/n]")
        $reply = Read-Host
        if (-not $reply -or $reply -match "^[Yy]") {
            & nautilus
        }
    } else {
        Write-Host (W-Y "  Skip auto-launch (module not active in this session).")
        Write-Host (W-C "  Next: open a new PowerShell window, then run:  nautilus")
    }
}
