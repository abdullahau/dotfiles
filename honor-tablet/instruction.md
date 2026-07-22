# Instructions

## Install Android SDK Platform Tools

```bash
brew install android-platform-tools
```

## Enable debugging on the tablet

- Settings → About tablet → tap Build number seven times.
- Settings → System & updates → Developer options → turn on USB debugging.
- On MagicOS, also disable "Monitor ADB install apps" if present — it blocks some commands.
- Plug in, set USB mode to File Transfer, and accept the RSA fingerprint prompt on the tablet.

## Verify the connection

```bash
adb devices
```

This should display a serial number followed by device.

## Remove a package

```bash
adb shell pm uninstall --user 0 <package-name>
```

## Save list of currently installed packages

```bash
adb shell pm list packages > packages.txt
```

## Run automated package removal script

```
./debloat.sh packages-remove.txt
```

## Exit device adb

```bash
adb kill-server
```

## Uninstall Android SDK Platform Tools

```bash
brew uninstall --cask android-platform-tools
```
