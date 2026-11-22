#!/bin/bash
# Compila Copista e crea build/Copista.app
# Requisito: Xcode Command Line Tools (xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Copista.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# ponytail: universal = due compilazioni (arm64 + x86_64) unite con lipo; minimo macOS 11
T=$(mktemp -d)
for A in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$A-apple-macos11.0" Sources/*.swift -o "$T/Copista-$A"
done
lipo -create "$T"/Copista-* -output "$APP/Contents/MacOS/Copista"
rm -rf "$T"
mkdir -p "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Fatto: $APP"
echo "Avvio: open $APP"
