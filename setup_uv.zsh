#!/usr/bin/env zsh

# uv is installed via Homebrew; ensure brew (and uv) are on PATH for this
# non-login script session.
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: 'uv' not found on PATH. Run setup_homebrew.zsh (which installs uv) first."
    exit 1
fi

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
