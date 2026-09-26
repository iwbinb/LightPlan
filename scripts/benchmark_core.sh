#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${1:-build/core-performance.json}"
ITERATIONS="${2:-5}"
mkdir -p "$(dirname "$OUTPUT")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# The same fixture is compiled with the actual core, not a simplified stand-in.
swiftc -O -whole-module-optimization -parse-as-library -module-name LightPlanCore packages/LightPlanCore/Sources/LightPlanCore/*.swift scripts/benchmark_core.swift -o "$WORK/benchmark"
"$WORK/benchmark" "$ITERATIONS" > "$OUTPUT"
echo "Release core measurements: $OUTPUT"
