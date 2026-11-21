#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
destination=${1:-"$PWD/artifacts"}
mkdir -p "$destination"
destination=$(cd "$destination" && pwd)
work=$(mktemp -d)
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$work"' EXIT

xcodebuild archive \
    -project Moonlight.xcodeproj -scheme Moonlight \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -archivePath "$work/StreamDesk.xcarchive" \
    IPHONEOS_DEPLOYMENT_TARGET=12.0 ARCHS=arm64 \
    PRODUCT_BUNDLE_IDENTIFIER=org.streamdesk.client \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    -disableAutomaticPackageResolution

app_dir="$work/StreamDesk.xcarchive/Products/Applications"
apps=("$app_dir"/*.app)
[[ ${#apps[@]} == 1 && -d ${apps[0]} ]]
app=${apps[0]}
plist="$app/Info.plist"
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
[[ $(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$plist") == 12.0 ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist") == org.streamdesk.client ]]
[[ $(xcrun lipo -archs "$app/$executable") == arm64 ]]
xcrun vtool -show-build "$app/$executable" > "$work/build-version.txt"
cat "$work/build-version.txt"
awk '$1 == "minos" && $2 ~ /^12\.0(\.0)?$/ { found = 1 }
     $1 == "version" && $2 ~ /^12\.0(\.0)?$/ { found = 1 }
     END { exit !found }' "$work/build-version.txt"

mkdir "$work/Payload"
ditto "$app" "$work/Payload/${app##*/}"
ditto -c -k --keepParent "$work/Payload" "$destination/StreamDesk-iOS12-unsigned.ipa"
unzip -tq "$destination/StreamDesk-iOS12-unsigned.ipa"
