#!/bin/bash
# Compila Copista e crea build/Copista.app
# Requisito: Xcode Command Line Tools (xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Copista.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/Copista"
mkdir -p "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Fatto: $APP"
echo "Avvio: open $APP"
