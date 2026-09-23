#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
STAGE="${1:-all}"
if [[ "$STAGE" == all ]]; then
  # Preserve the existing local entrypoint, but retain independent stage results.
  stages="$(python3 scripts/ci_baseline.py stages)"
  test -n "$stages"
  failed=0
  while IFS= read -r stage; do
    if ! bash scripts/ci_native.sh "$stage"; then failed=1; fi
  done <<< "$stages"
  exit "$failed"
fi
python3 scripts/ci_baseline.py stages | grep -Fxq "$STAGE" || { echo "Unknown CI stage: $STAGE" >&2; exit 2; }
E="$ROOT/build/evidence/$STAGE"
DERIVED="$ROOT/build/native/$STAGE/DerivedData"
mkdir -p "$E"
export NSUnbufferedIO=YES
# Each command's name and exact exit code remain available even on failure.
run() {
  local name="$1" code=0
  shift
  printf '\n>>> %s\n' "$name"
  if "$@" 2>&1 | tee "$E/$name.log"; then code=0; else code=$?; fi
  printf '%s\t%s\n' "$name" "$code" >> "$E/commands.tsv"
  return "$code"
}
printf '%s\n' "$STAGE" > "$E/stage.txt"
git rev-parse HEAD > "$E/source-commit.txt"
git status --porcelain > "$E/worktree-before.txt"
run toolchain xcodebuild -version
run swift-version xcrun swift --version
python3 scripts/ci_baseline.py inventory "$ROOT" > "$E/test-inventory.json"

if [[ "$STAGE" == checks ]]; then
  run ci-self-tests python3 scripts/ci_baseline_tests.py
  run localization python3 scripts/localization_audit.py
  run metadata python3 scripts/appstore_metadata_audit.py
  run release-preflight-tests python3 scripts/release_preflight_tests.py
  run screenshot-package-tests python3 scripts/package_store_screenshots_tests.py
  run validation-environment python3 -m venv build/release-validation
  run validation-dependencies build/release-validation/bin/python -m pip install --timeout 30 --retries 2 -r appstore/release_validation_requirements.txt
  run release-schema-tests build/release-validation/bin/python scripts/release_schema_tests.py
  # Do not overwrite locally edited generated configuration merely to test it.
  run generator-clean-input git diff --exit-code HEAD -- LightPlan.xcodeproj ios/Config/Project.xcconfig ios/LightPlan/Info.plist ios/LightPlanWidget/Info.plist
  run generator python3 scripts/generate_project.py
  run generator-drift git diff --exit-code HEAD -- LightPlan.xcodeproj ios/Config/Project.xcconfig ios/LightPlan/Info.plist ios/LightPlanWidget/Info.plist
  run core-tests swift test --package-path packages/LightPlanCore
  run debug-build xcodebuild -project LightPlan.xcodeproj -scheme LightPlan -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build
  run release-archive xcodebuild -project LightPlan.xcodeproj -scheme LightPlan -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" -archivePath "$E/LightPlan.xcarchive" CODE_SIGNING_ALLOWED=NO archive
  ARCHIVED_APP="$E/LightPlan.xcarchive/Products/Applications/LightPlan.app"
  test -d "$ARCHIVED_APP"
  if find "$ARCHIVED_APP" -name '*.storekit' -print -quit | grep -q .; then
    echo 'ERROR: StoreKit fixture in Release bundle' >&2; exit 1
  fi
  printf 'Unsigned Release archive; no StoreKit fixture. Not distribution signing or App Store approval.\n' > "$E/archive-check.txt"
  exit 0
fi

python3 scripts/ci_baseline.py select "$ROOT" "$STAGE" > "$E/selected-tests.txt"
SELECTORS=()
while IFS= read -r test; do SELECTORS+=("-only-testing:$test"); done < "$E/selected-tests.txt"
test "${#SELECTORS[@]}" -gt 0
NAME='iPhone 17 Pro'
if [[ "$STAGE" == ipad-* ]]; then NAME='iPad Pro 11-inch (M4)'; fi
xcrun simctl list devices available -j > "$E/simulators.json"
DEVICE_ID=$(python3 scripts/ci_baseline.py device "$E/simulators.json" "$NAME")
printf '%s\t%s\n' "$NAME" "$DEVICE_ID" > "$E/device-selection.tsv"
# Never erase or reset a developer's existing simulator. Only stop the selected
# simulator if this invocation booted it; the CI runner itself is ephemeral.
BOOTED_BY_US=0
cleanup() {
  code=$?
  trap - EXIT
  printf '%s\n' "$code" > "$E/stage-exit-code.txt"
  if [[ "$BOOTED_BY_US" == 1 ]]; then xcrun simctl shutdown "$DEVICE_ID" >> "$E/cleanup.log" 2>&1 || true; fi
  exit "$code"
}
trap cleanup EXIT
STATE=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(next(x["state"] for rows in d["devices"].values() for x in rows if x["udid"]==sys.argv[2]))' "$E/simulators.json" "$DEVICE_ID")
if [[ "$STATE" != Booted ]]; then run simulator-boot xcrun simctl boot "$DEVICE_ID"; BOOTED_BY_US=1; fi
run simulator-ready xcrun simctl bootstatus "$DEVICE_ID" -b
run status-bar xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
run debug-build xcodebuild -project LightPlan.xcodeproj -scheme LightPlan -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build
SIM_APP="$DERIVED/Build/Products/Debug-iphonesimulator/LightPlan.app"
APP_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$SIM_APP/Info.plist")
run install xcrun simctl install "$DEVICE_ID" "$SIM_APP"
run location-permission xcrun simctl privacy "$DEVICE_ID" grant location "$APP_ID"
run known-location xcrun simctl location "$DEVICE_ID" set 24.4478,118.0679
# Keep XCTest failures and attachments; avoid optional heavyweight sysdiagnose
# collection delaying a failed runner. The actual available option is recorded.
xcodebuild -help > "$E/xcodebuild-help.txt" 2>&1
TEST_OPTIONS=(-parallel-testing-enabled NO)
if grep -q -- '-collect-test-diagnostics' "$E/xcodebuild-help.txt"; then TEST_OPTIONS+=(-collect-test-diagnostics never); fi
printf '%s\n' "${TEST_OPTIONS[*]}" > "$E/diagnostics-policy.txt"
TEST_CODE=0
run native-tests xcodebuild -project LightPlan.xcodeproj -scheme LightPlan -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath "$DERIVED" -resultBundlePath "$E/native.xcresult" "${TEST_OPTIONS[@]}" "${SELECTORS[@]}" CODE_SIGNING_ALLOWED=NO test || TEST_CODE=$?
EXPORT_CODE=0
if [[ -d "$E/native.xcresult" ]]; then
  run attachments xcrun xcresulttool export attachments --path "$E/native.xcresult" --output-path "$E/screenshots" || EXPORT_CODE=$?
  xcrun xcresulttool get test-results summary --path "$E/native.xcresult" > "$E/test-summary.json" 2> "$E/test-summary-error.log" || EXPORT_CODE=$?
else
  echo 'No native result bundle was produced' >&2; EXPORT_CODE=1
fi
# Keep actionable assertions in the top-level log rather than only attachment names.
if [[ -s "$E/test-summary.json" ]]; then cat "$E/test-summary.json"; fi
# Export failures never conceal an original xcodebuild failure.
if [[ "$TEST_CODE" != 0 ]]; then exit "$TEST_CODE"; fi
if [[ "$EXPORT_CODE" != 0 ]]; then exit "$EXPORT_CODE"; fi
run test-count-check python3 scripts/ci_baseline.py summary "$E/test-summary.json" "${#SELECTORS[@]}"
