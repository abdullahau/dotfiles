#!/usr/bin/env zsh
#
# setup_homebrew.zsh — install Homebrew and everything in packages/Brewfile
# (formulae, casks, uv tools, and npm packages).
#
# Inputs:
#   packages/Brewfile — refresh it with:
#     brew bundle dump --describe --force --file=./packages/Brewfile
#
# Idempotent and safe to re-run.

echo "\n<<< Starting Homebrew Setup >>>\n"

if command -v brew >/dev/null 2>&1; then
	echo "brew exists, skipping install"
else
	echo "brew doesn't exist, continuing with install"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# The installer does not touch PATH for the current process.
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Trust non-core taps so `brew bundle` does not stop for a prompt.
brew trust --tap philocalyst/tap
brew trust --formula philocalyst/tap/caligula

brew bundle --verbose --file=./packages/Brewfile

