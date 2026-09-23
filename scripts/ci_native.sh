#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/evidence
xcodebuild -version | tee build/evidence/toolchain.txt
xcrun swift --version | tee -a build/evidence/toolchain.txt
python3 scripts/localization_audit.py
python3 scripts/appstore_metadata_audit.py
python3 scripts/release_preflight_tests.py
python3 scripts/package_store_screenshots_tests.py
python3 -m venv build/release-validation
build/release-validation/bin/python -m pip install -r appstore/release_validation_requirements.txt
build/release-validation/bin/python scripts/release_schema_tests.py
python3 scripts/generate_project.py
git diff --exit-code -- LightPlan.xcodeproj ios/Config/Project.xcconfig ios/LightPlan/Info.plist ios/LightPlanWidget/Info.plist
swift test --package-path packages/LightPlanCore 2>&1 | tee build/evidence/core-tests.log
xcodebuild -project LightPlan.xcodeproj -scheme LightPlan -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/evidence/debug-build.log
xcodebuild -project LightPlan.xcodeproj -scheme LightPlan -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData -archivePath build/LightPlan.xcarchive CODE_SIGNING_ALLOWED=NO archive 2>&1 | tee build/evidence/release-archive.log
# This is a paid-download app. No StoreKit test configuration belongs in the shipping bundle.
ARCHIVED_APP="build/LightPlan.xcarchive/Products/Applications/LightPlan.app"
test -d "$ARCHIVED_APP"
if find "$ARCHIVED_APP" -name '*.storekit' -print -quit | grep -q .; then
  echo "ERROR: StoreKit test configuration leaked into the Release app bundle." >&2
  exit 1
fi
# Never choose an invented device or assume a stable hosted-runner UDID.
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; candidates=[(r,x) for r,rows in d.items() if "iOS-26" in r for x in rows if x.get("isAvailable") and x["name"]=="iPhone 17 Pro"]; candidates.sort(key=lambda v:v[0]); print(candidates[-1][1]["udid"] if candidates else "")')
test -n "$DEVICE_ID"
xcrun simctl boot "$DEVICE_ID" || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
# The GPS flow must use a real Simulator location rather than treating a
# location-unavailable error as success. Install the built app before TCC grant.
SIM_APP="build/DerivedData/Build/Products/Debug-iphonesimulator/LightPlan.app"
APP_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$SIM_APP/Info.plist")
xcrun simctl install "$DEVICE_ID" "$SIM_APP"
xcrun simctl privacy "$DEVICE_ID" grant location "$APP_ID"
xcrun simctl location "$DEVICE_ID" set 24.4478,118.0679
xcodebuild -project LightPlan.xcodeproj -scheme LightPlan -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build/DerivedData -resultBundlePath build/evidence/iPhone.xcresult -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test 2>&1 | tee build/evidence/iphone-tests.log
xcrun xcresulttool export attachments --path build/evidence/iPhone.xcresult --output-path build/evidence/iphone-screenshots
# iPad is a wide-layout test, not evidence of an actual folding iPhone.
IPAD_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; c=[(r,x) for r,rows in d.items() if "iOS-26" in r for x in rows if x.get("isAvailable") and x["name"]=="iPad Pro 11-inch (M4)"]; c.sort(key=lambda v:v[0]); print(c[-1][1]["udid"] if c else "")')
test -n "$IPAD_ID"
xcrun simctl shutdown "$DEVICE_ID" || true
xcrun simctl boot "$IPAD_ID" || true
xcrun simctl bootstatus "$IPAD_ID" -b
xcodebuild -project LightPlan.xcodeproj -scheme LightPlan -configuration Debug -destination "platform=iOS Simulator,id=$IPAD_ID" -derivedDataPath build/DerivedData -resultBundlePath build/evidence/iPad.xcresult -parallel-testing-enabled NO -only-testing:LightPlanUITests/VisualUITests/testDarkScreenAndRotationContinuity CODE_SIGNING_ALLOWED=NO test 2>&1 | tee build/evidence/ipad-tests.log
xcrun xcresulttool export attachments --path build/evidence/iPad.xcresult --output-path build/evidence/ipad-screenshots
