#!/usr/bin/env zsh

echo "\n<<< Starting macOS Setup >>>\n"

osascript -e 'tell application "System Preferences" to quit'

# Finder Settings
# Finder > View > Show Path Bar
defaults write com.apple.finder "ShowPathbar" -bool "true"
# Finder > View > as Columns
defaults write com.apple.finder "FXPreferredViewStyle" -string "clmv"
# File Extension Change Warning
defaults write com.apple.finder "FXEnableExtensionChangeWarning" -bool "false"
# Save to disk location (not iCloud)
defaults write NSGlobalDomain "NSDocumentSaveNewDocumentsToCloud" -bool "false"

# Dock Settings
# Dock Icon Size
defaults write com.apple.dock "tilesize" -int "36"
# Dock Magnification State and Size
defaults write com.apple.dock magnification -bool true
defaults write com.apple.dock largesize -int 73
# Dock Auto-Hide State and Timer
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-time-modifier -float 0.25
defaults write com.apple.dock autohide-delay -float 0.1

# Mission Control 
# Group windows by application
defaults write com.apple.dock expose-group-apps -bool true

# Spaces & Display 
# Displays have separate Spaces System Settings → Desktop & Dock → Displays have separate Spaces
# defaults write com.apple.spaces spans-displays -bool true 
# killall SystemUIServer


# Finish macOS Setup
killall Finder
killall Dock

echo "\n<<< macOS Setup Complete.
    A logout or restart might be necessary. >>>\n"
