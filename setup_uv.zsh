#!/usr/bin/env zsh

PACKAGE_LIST_PATH="packages/uv-tools"

cat "$PACKAGE_LIST_PATH" | while read -r tool_package; do
    tool_package=$(echo "$tool_package" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [[ -n "$tool_package" && "$tool_package" != "#"* ]]; then
        echo "\n-> Attempting to install: $tool_package"
        if uv tool install "$tool_package"; then
            echo "   ✅ Successfully installed $tool_package."
        else
            # uv often reports details on failure, so we just log the outcome here.
            echo "   ❌ Installation failed for $tool_package. Check the error message above."
        fi
    fi
done
