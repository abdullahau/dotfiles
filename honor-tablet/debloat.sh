#!/bin/bash
# debloat.sh — usage: ./debloat.sh remove.txt
set -uo pipefail

LIST="${1:?usage: $0 <file>}"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="removed-$STAMP.txt"

# one snapshot of what's currently installed for user 0
INSTALLED=$(adb shell pm list packages --user 0 2>/dev/null \
            | tr -d '\r' | sed 's/^package://')
[[ -z "$INSTALLED" ]] && { echo "No adb device or empty list."; exit 1; }

ok=0; skip=0; fail=0

while read -r pkg; do
  pkg=$(echo "$pkg" | tr -d '\r' | xargs)          # trim whitespace
  [[ -z "$pkg" || "$pkg" == \#* ]] && continue

  if ! grep -qxF "$pkg" <<< "$INSTALLED"; then
    printf 'skip    %s (already absent)\n' "$pkg"
    ((skip++)); continue
  fi

  out=$(adb shell pm uninstall --user 0 "$pkg" </dev/null 2>&1 | tr -d '\r')
  case "$out" in
    Success*)
      echo "$pkg" >> "$LOG"
      printf 'ok      %s\n' "$pkg"; ((ok++)) ;;
    *"not installed for 0"*|*DELETE_FAILED_INTERNAL_ERROR*)
      printf 'skip    %s (%s)\n' "$pkg" "$out"; ((skip++)) ;;
    *)
      printf 'FAILED  %s -> %s\n' "$pkg" "$out"; ((fail++)) ;;
  esac
done < "$LIST"

printf '\n%d removed, %d skipped, %d failed\n' "$ok" "$skip" "$fail"
[[ $ok -gt 0 ]] && echo "Log: $LOG"
