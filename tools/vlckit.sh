#!/bin/bash
# Henter VLCKit (VideoLAN, LGPL 2.1) til Vendor/: TVVLCKit for Apple TV og MobileVLCKit for iPhone og iPad, de ferdige
# rammeverkene VideoLAN legger ut (de samme som i CocoaPods). Sjekksummen sjekkes. Rammeverkene settes sammen på nytt
# uten dSYM-ene, og MobileVLCKit bare med arm64 på enheten (den har også armv7, som ikke hører hjemme i en app for
# iOS 17) og arm64 og x86_64 i simulatoren.
# Bruk: tools/vlckit.sh [tvOS] [iOS]   (uten argumenter: begge; trenger en Mac)
set -euo pipefail
cd "$(dirname "$0")/.."
BASE=https://download.videolan.org/pub/cocoapods/prod

hent() { # navn fil sha256
  local name=$1 file=$2 sum=$3
  local out="Vendor/$name.xcframework"
  if [ -f "$out/.fyrlys-$sum" ]; then
    echo "$name finnes fra før"
    return
  fi
  local tmp
  tmp=$(mktemp -d)
  echo "Henter $file"
  curl -fsSL --retry 3 -o "$tmp/vlckit.tar.xz" "$BASE/$file"
  echo "$sum  $tmp/vlckit.tar.xz" | shasum -a 256 -c -
  tar -xf "$tmp/vlckit.tar.xz" -C "$tmp"
  local src="$tmp/$name-binary/$name.xcframework"
  local args=()
  for slice in "$src"/*/; do
    local fw="$slice$name.framework"
    [ -d "$fw" ] || continue
    rm -rf "$fw/_CodeSignature"
    local remove=()
    for arch in $(lipo -archs "$fw/$name"); do
      case "$arch" in
        arm64|x86_64) ;;
        *) remove+=(-remove "$arch") ;;
      esac
    done
    if [ ${#remove[@]} -gt 0 ]; then
      lipo "$fw/$name" "${remove[@]}" -output "$tmp/tynn"
      mv "$tmp/tynn" "$fw/$name"
      echo "  $(basename "$slice"): $(lipo -archs "$fw/$name")"
    fi
    args+=(-framework "$fw")
  done
  rm -rf "$out"
  mkdir -p Vendor
  xcodebuild -create-xcframework "${args[@]}" -output "$out" > /dev/null
  cp "$tmp/$name-binary/COPYING.txt" "$out/COPYING.txt"
  touch "$out/.fyrlys-$sum"
  rm -rf "$tmp"
  du -sh "$out"
}

platforms=("$@")
[ ${#platforms[@]} -gt 0 ] || platforms=(tvOS iOS)
for p in "${platforms[@]}"; do
  case "$p" in
    tvOS) hent TVVLCKit TVVLCKit-3.7.2-3e42ae47-79128878.tar.xz \
            fa264c2eb17d648669d9d12b51e76e5b6769828354517d09b340387b30825f58 ;;
    iOS) hent MobileVLCKit MobileVLCKit-3.7.2-3e42ae47-79128878.tar.xz \
            77b867667e5e62aa4062e71b7a4f76a0e2f505425916091c0eb0f94d9ad4af80 ;;
    *) echo "ukjent plattform: $p" >&2; exit 2 ;;
  esac
done
