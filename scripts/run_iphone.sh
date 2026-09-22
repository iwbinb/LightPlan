#!/bin/bash
# Build, install and launch on an explicitly selected iPhone without attaching LLDB.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 1 || "$1" == "--help" ]]; then
  echo 'Usage: bash scripts/run_iphone.sh <device-name-or-UDID>'
  echo 'List devices: xcrun devicectl list devices'
  echo 'Set DEVELOPMENT_TEAM in ios/Config/Local.xcconfig before running.'
  [[ "${1:-}" == "--help" ]] && exit 0
  exit 2
fi

device="$1"
derived_data="${LIGHTPLAN_DERIVED_DATA:-$PWD/DerivedData/iPhone}"
xcodebuild -project LightPlan.xcodeproj -scheme LightPlan \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_data" -allowProvisioningUpdates build

app="$derived_data/Build/Products/Debug-iphoneos/LightPlan.app"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
codesign --verify --deep --strict "$app"
xcrun devicectl device install app --device "$device" "$app"
xcrun devicectl device process launch --device "$device" "$bundle_id"
