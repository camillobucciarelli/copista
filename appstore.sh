#!/bin/bash
# Crea build/Copista.pkg firmato per il Mac App Store e lo carica su App Store Connect
# Uso: BUILD_NUMBER=N ./appstore.sh [--no-upload]
set -euo pipefail
cd "$(dirname "$0")"

SIGN_APP="${SIGN_APP:-Apple Distribution: Camillo Bucciarelli (A8QUU5F9G3)}"
SIGN_PKG="${SIGN_PKG:-3rd Party Mac Developer Installer: Camillo Bucciarelli (A8QUU5F9G3)}"
PROFILE="${PROFILE:-$HOME/.private_keys/Copista_AppStore.provisionprofile}"
: "${BUILD_NUMBER:?BUILD_NUMBER mancante}"

# Controlli preliminari
ids=$(security find-identity -v)
missing=""
grep -qF "\"$SIGN_APP\"" <<<"$ids" || missing+=$'\n  certificato app mancante: '"$SIGN_APP"
grep -qF "\"$SIGN_PKG\"" <<<"$ids" || missing+=$'\n  certificato installer mancante: '"$SIGN_PKG"
[ -f "$PROFILE" ] || missing+=$'\n  provisioning profile mancante: '"$PROFILE"
if [ -n "$missing" ]; then
  echo "Prerequisiti mancanti:$missing" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
if [[ "${GITHUB_REF_NAME:-}" == v* && "$GITHUB_REF_NAME" != "v$VERSION" ]]; then
  echo "Il tag $GITHUB_REF_NAME non corrisponde alla versione in Info.plist (v$VERSION)" >&2
  exit 1
fi

CI=true ./build.sh
APP="build/Copista.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
install -m 644 "$PROFILE" "$APP/Contents/embedded.provisionprofile"
xattr -cr "$APP"
codesign --force --options runtime --entitlements Copista.entitlements --sign "$SIGN_APP" "$APP"
productbuild --component "$APP" /Applications --sign "$SIGN_PKG" build/Copista.pkg
echo "Fatto: build/Copista.pkg"

[ "${1:-}" = "--no-upload" ] && exit 0
: "${ASC_KEY_ID:?ASC_KEY_ID mancante}" "${ASC_ISSUER_ID:?ASC_ISSUER_ID mancante}"
# la chiave AuthKey_<ASC_KEY_ID>.p8 viene cercata da altool in ~/.private_keys
xcrun altool --upload-app -f build/Copista.pkg -t macos --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID"
