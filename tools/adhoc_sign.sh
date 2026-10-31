#!/bin/sh
# Signerer et arkiv bygget uten signering (CODE_SIGNING_ALLOWED=NO) ad hoc, med app-id og team i rettighetene, så
# «xcodebuild -exportArchive» har dem når den signerer for App Store. Å bygge signert for en Apple TV ville krevd en
# utviklerprofil, og den krever en registrert enhet.
# Bruk: APPLE_TEAM_ID=… tools/adhoc_sign.sh build/Fyrlys.xcarchive
set -eu
team="${APPLE_TEAM_ID:?APPLE_TEAM_ID mangler}"
app="$1/Products/Applications/Fyrlys.app"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/rettigheter.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>$team.no.fyrlys.tv</string>
  <key>com.apple.developer.team-identifier</key><string>$team</string>
</dict></plist>
EOF
# rammeverk inni appen først (det er ingen nå, men pakker kan bli det)
if [ -d "$app/Frameworks" ]; then
  find "$app/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -exec \
    codesign --force --sign - --timestamp=none {} \;
fi
codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements "$tmp/rettigheter.plist" "$app"
codesign --verify --deep --strict "$app"
echo "Signert ad hoc: $app"
