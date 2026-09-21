#!/usr/bin/env bash
# Non-interactive smoke for Nautilus TUI on Linux (tmux PTY).
# Covers: chrome paint, slash menu, Esc-clear (no //theme), theme expand, rich fence chrome.
set -euo pipefail
S=nautilus-smoke
COLS=120; ROWS=40
MOD="${HOME}/.nautilus/Nautilus/Nautilus.psd1"
tmux kill-session -t "$S" 2>/dev/null || true
tmux new-session -d -s "$S" -x "$COLS" -y "$ROWS"
tmux send-keys -t "$S" "export TERM=xterm-256color COLUMNS=$COLS LINES=$ROWS; pwsh -NoLogo" Enter
sleep 1
tmux send-keys -t "$S" "Import-Module '$MOD' -Force; nautilus" Enter
sleep 4
OUT=$(tmux capture-pane -t "$S" -p -S -60)
echo "$OUT" | head -8
echo "$OUT" | grep -qE '0\.4\.3\.|N A U T I L U S|Nautilus' || { echo FAIL: no chrome; exit 1; }
# Rich fence chrome (when history has a fenced assistant reply)
if echo "$OUT" | grep -q 'Get-Date\|Write-Host\|powershell snippet'; then
  echo "$OUT" | grep -qE '─ .*powershell|copy code' || { echo FAIL: rich chrome missing; exit 1; }
  echo "$OUT" | grep -q '```' && { echo FAIL: raw fence leaked; exit 1; } || true
  echo "RICH CHROME OK"
fi

# Slash menu
tmux send-keys -t "$S" '/'
sleep 1
OUT=$(tmux capture-pane -t "$S" -p)
echo "$OUT" | grep -qE '/theme|/help|/clear|Session' || { echo FAIL: slash menu; exit 1; }

# Esc dismiss must clear buffer so next /theme is not //theme
tmux send-keys -t "$S" Escape
sleep 0.6
tmux send-keys -t "$S" '/theme'
sleep 0.8
OUT=$(tmux capture-pane -t "$S" -p)
if echo "$OUT" | grep -q '//theme'; then
  echo "FAIL: Esc left slash residue (//theme)"
  echo "$OUT" | tail -15
  exit 1
fi
echo "$OUT" | grep -qiE '/theme' || { echo FAIL: /theme after Esc; exit 1; }
echo "ESC CLEAR OK"

# Theme expand (Right)
tmux send-keys -t "$S" Right
sleep 0.8
OUT=$(tmux capture-pane -t "$S" -p)
echo "$OUT" | grep -qiE 'Midnight|Cyber|Abyss|Nautilus' || { echo FAIL: theme expand; exit 1; }

tmux send-keys -t "$S" Escape Escape Escape
sleep 1
tmux kill-session -t "$S" 2>/dev/null || true

pwsh -NoLogo -Command '
  $psm1 = Join-Path $HOME ".nautilus/Nautilus/Nautilus.psm1"
  $psd1 = Join-Path $HOME ".nautilus/Nautilus/Nautilus.psd1"
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($psm1, [ref]$tok, [ref]$err)
  if ($err -and $err.Count) { $err | ForEach-Object { $_.ToString() }; exit 1 }
  Write-Host "PARSE OK"
  $raw = Get-Content -LiteralPath $psm1 -Raw
  $man = Get-Content -LiteralPath $psd1 -Raw
  if ($raw -notmatch "function script:Get-ThemeBgCode") { Write-Host "FAIL: Get-ThemeBgCode missing"; exit 1 }
  if ($raw -notmatch "function script:Get-CanvasBgAnsi") { Write-Host "FAIL: Get-CanvasBgAnsi missing"; exit 1 }
  if ($raw -notmatch "bg\s*=\s*23[234]") { Write-Host "FAIL: theme bg missing"; exit 1 }
  Write-Host "CANVAS HELPERS OK"
  if ($raw -notmatch "0\.4\.3\.5" -or $man -notmatch "0\.4\.3\.5") { Write-Host "FAIL: version not 0.4.3.5"; exit 1 }
  # 0.4.3.5 relaunch bootstrap hardening
  $mFresh = [regex]::Match($raw, "function script:Start-NautilusFreshSession\s*\{(?<body>.*?)\nfunction script:Run-Update", "Singleline")
  if (-not $mFresh.Success) { Write-Host "FAIL: Start-NautilusFreshSession body not found"; exit 1 }
  $fresh = $mFresh.Groups["body"].Value
  if ($fresh -notmatch "-NoProfile") { Write-Host "FAIL: relaunch missing -NoProfile"; exit 1 }
  if ($fresh -notmatch "-File") { Write-Host "FAIL: relaunch missing -File"; exit 1 }
  if ($fresh -notmatch "relaunch\.ps1") { Write-Host "FAIL: relaunch.ps1 wrapper missing"; exit 1 }
  if ($fresh -notmatch "Start-Sleep\s+-Seconds\s+3") { Write-Host "FAIL: child sleep missing (want 3s)"; exit 1 }
  if ($fresh -notmatch "KeyAvailable") { Write-Host "FAIL: key drain missing"; exit 1 }
  if ($fresh -notmatch "ReadKey") { Write-Host "FAIL: ReadKey drain missing"; exit 1 }
  if ($fresh -notmatch "TreatControlCAsInput") { Write-Host "FAIL: TreatControlCAsInput reset missing"; exit 1 }
  if ($fresh -notmatch "FlushConsoleInputBuffer") { Write-Host "FAIL: FlushConsoleInputBuffer missing"; exit 1 }
  if ($fresh -notmatch "Clear-Host") { Write-Host "FAIL: Clear-Host after Import missing"; exit 1 }
  if ($fresh -notmatch "UseShellExecute") { Write-Host "FAIL: UseShellExecute Windows spawn missing"; exit 1 }
  if ($fresh -notmatch "WorkingDirectory") { Write-Host "FAIL: WorkingDirectory missing"; exit 1 }
  if ($raw -notmatch "Start-Sleep\s+-Milliseconds\s+2200") { Write-Host "FAIL: parent sleep not ~2200ms"; exit 1 }
  if ($raw -notmatch "function script:Reset-NautilusConsole") { Write-Host "FAIL: Reset-NautilusConsole missing"; exit 1 }
  Write-Host "RELAUNCH BOOTSTRAP OK"
  if ($raw -match "RawUI\.(Background|Foreground)Color\s*=") { Write-Host "FAIL: RawUI color assign still present"; exit 1 }
  if ($raw -match "SavedRawUi") { Write-Host "FAIL: SavedRawUi still referenced"; exit 1 }
  $m = [regex]::Match($raw, "function script:Enter-TUI\s*\{(?<body>.*?)\nfunction script:Exit-TUI", "Singleline")
  if (-not $m.Success) { Write-Host "FAIL: Enter-TUI body not found"; exit 1 }
  $body = $m.Groups["body"].Value
  if ($body -match "RawUI\.(Background|Foreground)Color\s*=") { Write-Host "FAIL: Enter-TUI still assigns RawUI colors"; exit 1 }
  $idx2j = $body.IndexOf("2J")
  $idxMouse = $body.IndexOf("Enable-Mouse")
  $idxVt = $body.LastIndexOf("Enable-VT")
  if ($idx2j -lt 0 -or $idxVt -lt 0) { Write-Host "FAIL: canvas 2J or Enable-VT missing in Enter-TUI"; exit 1 }
  if ($idxVt -le $idx2j) { Write-Host "FAIL: Enable-VT must run after canvas 2J"; exit 1 }
  if ($idxMouse -ge 0 -and $idxVt -le $idxMouse) { Write-Host "FAIL: Enable-VT must run after Enable-Mouse"; exit 1 }
  Write-Host "ENTER-TUI ORDER OK (no RawUI; Enable-VT after canvas)"
  # Runtime: import module and probe Enter/Exit + EnableVtCallCount via module SessionState
  Import-Module $psd1 -Force
  $mod = Get-Module Nautilus
  $sb = $mod.NewBoundScriptBlock({
    param()
    $script:EnableVtCallCount = 0
    Enable-VT
    $c1 = [int]$script:EnableVtCallCount
    try {
      $script:SavedConsoleBg = [Console]::BackgroundColor
      $script:SavedConsoleFg = [Console]::ForegroundColor
      [Console]::BackgroundColor = [ConsoleColor]::Black
      [Console]::ForegroundColor = [ConsoleColor]::Gray
    } catch { }
    $enterOk = $false
    try { Enter-TUI; $enterOk = $true } catch { Write-Host ("Enter-TUI catch: " + $_.Exception.Message) }
    $c2 = [int]$script:EnableVtCallCount
    if ($enterOk -and $c2 -le $c1) { throw "Enter-TUI did not invoke Enable-VT (count $c1 -> $c2)" }
    try { Exit-TUI } catch { Write-Host ("Exit-TUI catch: " + $_.Exception.Message) }
    "PROBE OK count=$c2 enterOk=$enterOk active=$($script:TuiActive)"
  })
  $result = & $sb
  Write-Host $result
'

echo "SMOKE OK"
