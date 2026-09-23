#!/usr/bin/env python3
"""Small, fail-closed helpers for the native CI baseline (Python standard library)."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

# Every native XCTest class belongs to one iPhone shard. New classes require
# explicit assignment; the audit fails rather than silently losing coverage.
PHONE = {
    "iphone-product": "ProductUITests",
    "iphone-planning": "RichPlanningUITests",
    "iphone-visual": "VisualUITests",
    "iphone-rich-visual": "RichVisualUITests",
    "iphone-accessibility": "AccessibilityUITests",
}
IPAD = "VisualUITests/testDarkScreenAndRotationContinuity"
STAGES = ("checks", *PHONE, "ipad-rotation")


def inventory(root):
    found = {}
    for path in sorted((Path(root) / "ios/LightPlanVisualUITests").glob("*.swift")):
        source = path.read_text(encoding="utf-8")
        classes = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source)
        methods = re.findall(r"\bfunc\s+(test\w+)\s*\(\s*\)", source)
        if not classes and not methods:
            continue  # Shared helpers are allowed, unassigned tests are not.
        if len(classes) != 1 or not methods or classes[0] in found:
            raise ValueError(f"Ambiguous or empty XCTest source: {path}")
        if len(methods) != len(set(methods)):
            raise ValueError(f"Duplicate XCTest methods: {path}")
        found[classes[0]] = sorted(methods)
    if set(found) != set(PHONE.values()):
        raise ValueError(f"Native shard coverage mismatch: {sorted(found)}")
    return found


def selection(root, stage):
    found = inventory(root)
    if stage in PHONE:
        name = PHONE[stage]
        selected = [f"{name}/{method}" for method in found[name]]
    elif stage == "ipad-rotation":
        name, method = IPAD.split("/")
        if method not in found[name]:
            raise ValueError(f"Missing iPad baseline test: {IPAD}")
        selected = [IPAD]
    else:
        raise ValueError(f"Not a UI stage: {stage}")
    return ["LightPlanUITests/" + item for item in selected]


def device(data, name):
    candidates = []
    for runtime, rows in data["devices"].items():
        if not re.search(r"\.iOS-26(?:-|$)", runtime):
            continue
        version = tuple(int(n) for n in runtime.rsplit("iOS-", 1)[1].split("-"))
        for row in rows:
            if row.get("isAvailable") and row.get("name") == name:
                candidates.append((version, row["udid"]))
    if not candidates:
        raise ValueError(f"No available iOS 26 simulator: {name}")
    return max(candidates)[1]


def validate_summary(data, expected):
    if expected < 1:
        raise ValueError("Empty expected test set")
    counts = [data.get(key) for key in ("passedTests", "failedTests", "skippedTests")]
    if any(type(value) is not int or value < 0 for value in counts):
        raise ValueError("Unrecognized xcresult test-count schema")
    if counts != [expected, 0, 0]:
        raise ValueError(f"Expected {expected} passes, zero failures/skips; got {counts}")


def bounded_run(command, log_path, seconds, grace=5):
    """Bound a whole stage, retain raw output, and reap its process group."""
    if not command or not math.isfinite(seconds) or seconds <= 0 or not math.isfinite(grace) or grace < 0:
        raise ValueError("A command and finite positive timeout are required")
    path = Path(log_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    result = {"command": command, "timeout_seconds": seconds,
              "commit": os.environ.get("GITHUB_SHA"), "exit_code": 125,
              "timed_out": False, "interrupted": False}
    process = None
    handlers = {}

    def interrupted(signum, _frame):
        raise InterruptedError(signum)

    def stop_group():
        if process is None:
            return
        # Even if the parent exits on TERM, descendants may ignore it.
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                break
            if sig == signal.SIGTERM:
                try:
                    process.wait(timeout=grace)
                except subprocess.TimeoutExpired:
                    pass
        process.wait()

    with path.open("x", encoding="utf-8") as output:
        try:
            for sig in (signal.SIGTERM, signal.SIGINT):
                handlers[sig] = signal.signal(sig, interrupted)
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            deadline = started + seconds
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(command, seconds)
                try:
                    code = process.wait(timeout=min(60, remaining))
                    result["exit_code"] = code if code >= 0 else 128 - code
                    break
                except subprocess.TimeoutExpired:
                    if time.monotonic() >= deadline:
                        raise
                    print(f"Native stage running; raw log: {path}", flush=True)
        except subprocess.TimeoutExpired:
            result.update(exit_code=124, timed_out=True)
            stop_group()
        except InterruptedError as error:
            result.update(exit_code=128 + error.args[0], interrupted=True)
            stop_group()
        except OSError as error:
            result["error"] = str(error)
        finally:
            for sig, handler in handlers.items():
                signal.signal(sig, handler)
            result["duration_seconds"] = round(time.monotonic() - started, 3)
            path.with_suffix(".json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)
    if result["exit_code"]:
        # Full output remains in the artifact. Keep hosted job logs bounded.
        from collections import deque
        with path.open(errors="replace") as source:
            print("".join(deque(source, maxlen=60)), end="")
    return result["exit_code"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("stages")
    audit = sub.add_parser("inventory")
    audit.add_argument("root", type=Path)
    select = sub.add_parser("select")
    select.add_argument("root", type=Path)
    select.add_argument("stage")
    sim = sub.add_parser("device")
    sim.add_argument("path", type=Path)
    sim.add_argument("name")
    summary = sub.add_parser("summary")
    summary.add_argument("path", type=Path)
    summary.add_argument("expected", type=int)
    run = sub.add_parser("run")
    run.add_argument("--seconds", type=float, required=True)
    run.add_argument("--log", type=Path, required=True)
    run.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        if args.action == "stages":
            print("\n".join(STAGES))
        elif args.action == "inventory":
            print(json.dumps(inventory(args.root), indent=2))
        elif args.action == "select":
            print("\n".join(selection(args.root, args.stage)))
        elif args.action == "device":
            print(device(json.loads(args.path.read_text()), args.name))
        elif args.action == "summary":
            validate_summary(json.loads(args.path.read_text()), args.expected)
            print(f"Verified {args.expected} native tests, no failures/skips")
        else:
            command = args.command[1:] if args.command[:1] == ["--"] else args.command
            return bounded_run(command, args.log, args.seconds)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"CI baseline error: {error}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
