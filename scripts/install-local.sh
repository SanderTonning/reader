#!/bin/zsh
# Bygger og installerer Reader lokalt: Mac-appen til /Applications og iOS-appen på en tilkoblet iPhone.
# Bruk: DEVELOPMENT_TEAM=<team-id> scripts/install-local.sh   (team-ID fra Xcode › Signing, gratis Apple-ID holder)
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen -q

xcodebuild build -project Reader.xcodeproj -scheme Reader_macOS -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet
pkill -x Reader || true
rm -rf /Applications/Reader.app
cp -R build/Build/Products/Debug/Reader.app /Applications/
echo "Mac: installert i /Applications/Reader.app"

device=$(xcrun devicectl list devices 2>/dev/null | grep -E 'iPhone.*(available|connected)' | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}' | head -1 || true)
if [[ -z "$device" || -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "iPhone: hoppet over (koble til telefonen og sett DEVELOPMENT_TEAM)"
  exit 0
fi
xcodebuild build -project Reader.xcodeproj -scheme Reader_iOS -destination 'generic/platform=iOS' \
  -derivedDataPath build -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" -quiet
xcrun devicectl device install app --device "$device" build/Build/Products/Debug-iphoneos/Reader.app >/dev/null
echo "iPhone: installert"
