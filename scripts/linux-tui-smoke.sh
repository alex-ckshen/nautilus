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
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($psm1, [ref]$tok, [ref]$err)
  if ($err -and $err.Count) { $err | ForEach-Object { $_.ToString() }; exit 1 }
  Write-Host "PARSE OK"
'
echo "SMOKE OK"
