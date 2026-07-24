#!/bin/zsh
# Best-effort integration smoke test. Requires Accessibility access for the
# terminal and creates temporary TextEdit/Calculator windows.
set -eu
cd "$(dirname "$0")"

if [[ ! -x ".build/release/RestoreLayout" ]]; then
  swift build -c release
fi

BINARY=".build/release/RestoreLayout"
if ! "$BINARY" --list >/dev/null; then
  echo "Grant Accessibility access to this terminal, then rerun." >&2
  exit 2
fi

open -a TextEdit
open -a Calculator
sleep 1
"$BINARY" --save

osascript <<'APPLESCRIPT'
tell application "System Events"
    if exists process "TextEdit" then
        set position of front window of process "TextEdit" to {80, 80}
        set size of front window of process "TextEdit" to {520, 420}
    end if
    if exists process "Calculator" then
        set position of front window of process "Calculator" to {700, 160}
    end if
end tell
APPLESCRIPT

sleep 0.2
"$BINARY" --restore
"$BINARY" --list
echo "Inspect the listed TextEdit/Calculator frames; restored values should be within 2pt."

