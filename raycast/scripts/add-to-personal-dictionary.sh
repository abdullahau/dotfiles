#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Add to Personal Dictionary
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📓
# @raycast.packageName Personal Tools

# Documentation:
# @raycast.description Append copied text to Logseq Personal Dictionary
# @raycast.author abdullah_au
# @raycast.authorURL https://raycast.com/abdullah_au

# Path to your Logseq markdown file
FILE="$HOME/Documents/Notes/Logseq/pages/Personal Dictionary.md"

# Get clipboard contents (the word/phrase you highlighted and copied)
TEXT=$(pbpaste)

printf "\n- %s" "$TEXT" >> "$FILE"

osascript -e 'on run argv
  display notification ("Added " & item 1 of argv & " to Personal Dictionary") with title "Raycast"
end run' "$TEXT"
