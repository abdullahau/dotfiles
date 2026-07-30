#!/usr/bin/env zsh

echo "\n<<< Starting Homebrew Setup >>>\n"

if command -v brew >/dev/null 2>&1; then
	echo "brew exists, skipping install"
else
	echo "brew doesn't exist, continuing with install"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure brew is on PATH for this non-login script session (installer does not
# modify PATH for the current process).
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Brewfile update method:
# `brew bundle dump --describe --force --file=./packages/Brewfile`
brew bundle --verbose --file=./packages/Brewfile

