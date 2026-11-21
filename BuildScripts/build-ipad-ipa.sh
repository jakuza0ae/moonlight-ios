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
    'WARNING_CFLAGS=$(inherited) -Werror=unguarded-availability-new' \
    -disableAutomaticPackageResolution

app_dir="$work/StreamDesk.xcarchive/Products/Applications"
apps=("$app_dir"/*.app)
[[ ${#apps[@]} == 1 && -d ${apps[0]} ]]
app=${apps[0]}
mkdir "$work/Payload"
ditto "$app" "$work/Payload/${app##*/}"
ditto -c -k --keepParent "$work/Payload" "$work/StreamDesk-iOS12-unsigned.ipa"
python3 BuildScripts/verify-ipad-ipa.py "$work/StreamDesk-iOS12-unsigned.ipa"
install -m644 "$work/StreamDesk-iOS12-unsigned.ipa" "$destination/"
