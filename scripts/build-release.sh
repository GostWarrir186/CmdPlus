#!/bin/zsh
# Builds a universal, ad-hoc signed CmdPlus.app and zips it for a GitHub release.
#
# Ad-hoc signing is free but not notarized, so macOS asks users to confirm the
# first launch (see "Download" in README.md).
#
# Usage: scripts/build-release.sh 0.1.0
set -euo pipefail

version=${1:?"usage: $0 <version>"}
root=${0:A:h:h}
build="$root/build/release"
out="$root/build/dist"

rm -rf "$build" "$out"
mkdir -p "$out"

xcodebuild -project "$root/CmdPlus.xcodeproj" -scheme CmdPlus -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$build" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  MARKETING_VERSION="$version" \
  build -quiet

app="$build/Build/Products/Release/CmdPlus.app"
# Folders synced with iCloud (like Desktop) add Finder attributes that break verification.
xattr -cr "$app"
codesign --verify --deep --strict "$app"

zip="$out/CmdPlus-$version.zip"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$zip"
(cd "$out" && shasum -a 256 "${zip:t}" | tee "${zip:t}.sha256")
echo "Built $zip"
