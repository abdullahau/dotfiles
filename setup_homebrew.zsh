#!/usr/bin/env zsh

echo "\n<<< Starting Homebrew Setup >>>\n"

if exists brew; then
	echo "brew exists, skipping install"
else
	echo "brew doesn't exist, continuing with install"
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Brewfile update method: 
# `brew bundle dump --describe --force --no-vscode --file=./packages/Brewfile`
# `brew bundle dump --describe --force --file=./packages/Brewfile`
brew bundle --verbose --file=./packages/Brewfile

# Should we wrap this in a conditional?
echo "Enter superuser (sudo) password to accept Xcode license"
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch

# echo "Installing VS Code Extensions"
# cat vscode_extensions | xargs -L 1 code --install-extension

# This works to solve the Insecure Directories issue:
# compaudit | xargs chmod go-w
# But this is from the Homebrew site, though `-R` was needed:
# https://docs.brew.sh/Shell-Completion#configuring-completions-in-zsh
chmod -R go-w "$(brew --prefix)/share"
