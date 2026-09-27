#!/bin/bash
# Native screenshot drafts only. Dedicated disposable Simulator, never a user's device.
set -euo pipefail
cd "$(dirname "$0")/.."
FAMILY="${1:-}"
case "$FAMILY" in
  iphone) DEVICE_NAME="${LIGHTPLAN_CAPTURE_DEVICE:-iPhone 17 Pro Max}";;
  ipad) DEVICE_NAME="${LIGHTPLAN_CAPTURE_DEVICE:-iPad Pro 13-inch (M4)}";;
  *) echo 'Usage: bash scripts/capture_store_screenshots.sh iphone|ipad NEW_OUTPUT_DIRECTORY' >&2; exit 2;;
esac
OUTPUT="${2:?Provide a new output directory}"
[[ ! -e "$OUTPUT" ]] || { echo 'Output already exists; preserve earlier evidence.' >&2; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { echo 'A clean committed checkout is required.' >&2; exit 2; }
command -v xcodebuild >/dev/null || { echo 'Apple Xcode is required.' >&2; exit 2; }
mkdir -p "$OUTPUT"
E="$(cd "$OUTPUT" && pwd)"
DEVICE_ID=''
cleanup() {
  code=$?
  trap - EXIT
  printf '%s\n' "$code" > "$E/exit-code.txt"
  if [[ -n "$DEVICE_ID" ]]; then
    # This ID was just created below, never selected from a user's installed devices.
    xcrun simctl shutdown "$DEVICE_ID" >> "$E/cleanup.log" 2>&1 || true
    xcrun simctl delete "$DEVICE_ID" >> "$E/cleanup.log" 2>&1 || true
  fi
  exit "$code"
}
trap cleanup EXIT
git rev-parse HEAD > "$E/source-commit.txt"
git rev-parse HEAD^{tree} > "$E/source-tree.txt"
xcodebuild -version > "$E/toolchain.txt"
xcrun simctl list devicetypes -j > "$E/device-types.json"
xcrun simctl list runtimes -j > "$E/runtimes.json"
python3 - "$E" "$DEVICE_NAME" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);name=sys.argv[2]
types=[x for x in json.loads((p/'device-types.json').read_text())['devicetypes'] if x['name']==name]
runtimes=[x for x in json.loads((p/'runtimes.json').read_text())['runtimes'] if x.get('isAvailable') and x.get('identifier','').startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
if len(types)!=1 or not runtimes: raise SystemExit('Requested native device type or iOS runtime unavailable; do not substitute resized screenshots')
runtime=max(runtimes,key=lambda x:tuple(int(y) for y in x['version'].split('.')))
(p/'device-type.txt').write_text(types[0]['identifier'])
(p/'runtime.txt').write_text(runtime['identifier'])
PY
DEVICE_ID=$(xcrun simctl create "LightPlan Store QA $FAMILY $$" "$(cat "$E/device-type.txt")" "$(cat "$E/runtime.txt")")
xcrun simctl boot "$DEVICE_ID"
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
TEST_CODE=0
xcodebuild -project LightPlan.xcodeproj -scheme LightPlan -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath "$E/DerivedData" \
  -resultBundlePath "$E/native.xcresult" -parallel-testing-enabled NO \
  -only-testing:LightPlanUITests/VisualUITests/testCoreScreensAllLanguages \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$E/tests.log" || TEST_CODE=$?
if [[ -d "$E/native.xcresult" ]]; then
  xcrun xcresulttool get test-results summary --path "$E/native.xcresult" > "$E/test-summary.json"
  xcrun xcresulttool export attachments --path "$E/native.xcresult" --output-path "$E/screenshots"
fi
[[ "$TEST_CODE" == 0 ]] || exit "$TEST_CODE"
python3 scripts/ci_baseline.py summary "$E/test-summary.json" 1
python3 - "$E" "$FAMILY" <<'PY'
import json,pathlib,sys
sys.path.insert(0,'scripts')
from package_store_screenshots import select_captures, metadata_locales
p=pathlib.Path(sys.argv[1]);family=sys.argv[2]
shots=select_captures(p/'screenshots', family, metadata_locales(pathlib.Path.cwd()))
assert len(shots)==27
(p/'capture-summary.json').write_text(json.dumps({'source_commit':(p/'source-commit.txt').read_text().strip(),'family':family,'native_captures':len(shots),'review_status':'pending','ready_for_submission':False},indent=2)+'\n')
PY
