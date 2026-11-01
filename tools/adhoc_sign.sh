#!/bin/sh
# Signerer et arkiv bygget uten signering (CODE_SIGNING_ALLOWED=NO) ad hoc, med app-id og team i rettighetene, så
# «xcodebuild -exportArchive» har dem når den signerer for App Store. Å bygge signert for en Apple TV ville krevd en
# utviklerprofil, og den krever en registrert enhet.
# Med ICLOUD_KVS=1 (satt av «asc.py check» når iCloud er slått på for app-id-en) også iCloud nøkkel–verdi-lagringen,
# felles for Apple TV, iPhone og iPad (samme app-id), for favorittene.
# Bruk: APPLE_TEAM_ID=… tools/adhoc_sign.sh build/Fyrlys.xcarchive
set -eu
team="${APPLE_TEAM_ID:?APPLE_TEAM_ID mangler}"
app="$1/Products/Applications/Fyrlys.app"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
icloud=""
if [ "${ICLOUD_KVS:-}" = "1" ]; then
  icloud="<key>com.apple.developer.ubiquity-kvstore-identifier</key><string>$team.no.fyrlys.tv</string>"
fi
# den felles nøkkelring-gruppen med Top Shelf (favorittene); appens egen gruppe først, så den er standard
shared="$team.no.fyrlys.tv.shared"
cat > "$tmp/rettigheter.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>$team.no.fyrlys.tv</string>
  <key>com.apple.developer.team-identifier</key><string>$team</string>
  <key>keychain-access-groups</key><array><string>$team.no.fyrlys.tv</string><string>$shared</string></array>
  $icloud
</dict></plist>
EOF
# utvidelsene (Top Shelf) først, med sin egen app-id og den felles gruppen
if [ -d "$app/PlugIns" ]; then
  for ext in "$app"/PlugIns/*.appex; do
    [ -d "$ext" ] || continue
    id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$ext/Info.plist")
    cat > "$tmp/utvidelse.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>$team.$id</string>
  <key>com.apple.developer.team-identifier</key><string>$team</string>
  <key>keychain-access-groups</key><array><string>$shared</string></array>
</dict></plist>
EOF
    codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements "$tmp/utvidelse.plist" "$ext"
    echo "Signert ad hoc: $ext ($id)"
  done
fi
# rammeverk inni appen først (det er ingen nå, men pakker kan bli det)
if [ -d "$app/Frameworks" ]; then
  find "$app/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -exec \
    codesign --force --sign - --timestamp=none {} \;
fi
codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements "$tmp/rettigheter.plist" "$app"
codesign --verify --deep --strict "$app"
echo "Signert ad hoc: $app"
