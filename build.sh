#!/bin/bash
# Compila Copista e crea build/Copista.app
# Requisito: Xcode Command Line Tools (xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Copista.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# ponytail: solo arm64; per universal serve una seconda compilazione x86_64 + lipo
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 Sources/*.swift -o "$APP/Contents/MacOS/Copista"
mkdir -p "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Fatto: $APP"
echo "Avvio: open $APP"
