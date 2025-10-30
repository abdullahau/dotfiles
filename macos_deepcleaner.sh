#!/usr/bin/env bash

# macOS Deep Cleaner (TUI) using fzf + fd
# Author: Abdullah Mahmood
# Requirements: fd, fzf, sudo

set -euo pipefail

#--------------------------------------
# CONFIGURATION
#--------------------------------------
EXCLUDE_DIRS=(
  "/System/Volumes"
  "/System/Library"
  "/Volumes"
  "/private/var/vm"
  "/dev"
  "/proc"
  "/sys"
  "/cores"
  "$HOME/Library/CloudStorage"
  "$HOME/.Trash/"
)

EXCLUDE_PATTERNS=(
  ".git"
  ".venv"
  ".vscode"
  ".positron"
)

fzf_args=(
  --multi
  --ansi
  --reverse
  --info=inline
  --prompt="🔍 Search keyword: "
  --header="↑/↓ navigate • TAB select • ENTER confirm • CTRL-C cancel"
  --color 'pointer:green,marker:green'
  --preview-window 'right:60%:wrap'
  --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up'
  --bind 'alt-k:preview-up,alt-j:preview-down'
)

# Optional: enable folder/file previews (set to false for speed)
PREVIEW_ENABLED=true
if [[ "$PREVIEW_ENABLED" == true ]]; then
  fzf_args+=(--preview '
    if [[ -d {} ]]; then
      echo "📁 Folder: {}"; ls -la "{}" | head -50
    else
      echo "📄 File: {}"; file "{}"; echo; head -50 "{}" 2>/dev/null
    fi
  ')
fi

#--------------------------------------
# MAIN LOGIC
#--------------------------------------
read -rp "Enter keyword to search for: " keyword
[[ -z "$keyword" ]] && echo "❌ Empty keyword, exiting." && exit 1

echo "🔎 Searching filesystem for '$keyword'... (please wait)"
sleep 1

# Build fd command
fd_cmd=(fd "$keyword" /
  --hidden
  --color never
  --type f
  --type d
  --type x  
  --ignore-file /dev/null
  --ignore-case
  --follow
  --threads=4
)

# Add directory excludes
for ex in "${EXCLUDE_DIRS[@]}"; do
  fd_cmd+=(--exclude "$ex")
done

# Add pattern excludes
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
  fd_cmd+=(--exclude "$pattern")
done

# Execute fd
results=$("${fd_cmd[@]}" 2>/dev/null | sort -u)

if [[ -z "$results" ]]; then
  echo "⚠️  No results found for '$keyword'."
  exit 0
fi

# Pipe to fzf for multi-select
selected=$(echo "$results" | fzf "${fzf_args[@]}")

if [[ -z "$selected" ]]; then
  echo "🚫 No selections made. Exiting."
  exit 0
fi

echo
echo "⚠️  You are about to delete the following items (recursively):"
echo "$selected"
read -rp "Are you sure? (y/N): " confirm
[[ "$confirm" != [yY] ]] && echo "Cancelled." && exit 0

echo "🗑️  Removing selected files/folders..."
echo "$selected" | while IFS= read -r path; do
  if [[ -n "$path" ]]; then
    # sudo rm -rfv "$path"
    sudo mv "$path" ~/.Trash/
  fi
done

echo "✅ Cleanup complete."
