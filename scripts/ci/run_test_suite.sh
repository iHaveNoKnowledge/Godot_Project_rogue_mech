#!/usr/bin/env bash
# Runs every tests/*_verify.tscn headless with a per-test timeout and fails
# the build if any test fails or hangs.
#
# Usage:
#   GODOT=/path/to/godot ./scripts/ci/run_test_suite.sh
#
# Env overrides:
#   GODOT          path to the Godot binary (default: "godot" on PATH)
#   TEST_TIMEOUT   per-test timeout in seconds (default: 60)
#   PROJECT_PATH   path to the project root (default: ".")
#   FAILED_LOG_DIR where per-test logs are kept (default: /tmp/godot_test_logs)
set -u

GODOT="${GODOT:-godot}"
TEST_TIMEOUT="${TEST_TIMEOUT:-60}"
PROJECT_PATH="${PROJECT_PATH:-.}"
FAILED_LOG_DIR="${FAILED_LOG_DIR:-/tmp/godot_test_logs}"

PASS=0
FAIL=0
HANG=0
ISSUES=()

mkdir -p "$FAILED_LOG_DIR"

for t in tests/*_verify.tscn; do
	[ -f "$t" ] || continue
	name=$(basename "$t" .tscn)
	log="$FAILED_LOG_DIR/$name.log"
	timeout "$TEST_TIMEOUT" "$GODOT" --headless --path "$PROJECT_PATH" "res://tests/$name.tscn" > "$log" 2>&1
	code=$?
	if [ "$code" -eq 0 ]; then
		PASS=$((PASS + 1))
		echo "PASS: $name"
	elif [ "$code" -eq 124 ]; then
		HANG=$((HANG + 1))
		ISSUES+=("HANG: $name")
		echo "HANG: $name (timed out after ${TEST_TIMEOUT}s)"
	else
		FAIL=$((FAIL + 1))
		ISSUES+=("FAIL: $name (exit $code)")
		echo "FAIL: $name (exit $code)"
	fi
done

echo ""
echo "=== SUMMARY ==="
echo "PASS=$PASS FAIL=$FAIL HANG=$HANG"
if [ "${#ISSUES[@]}" -gt 0 ]; then
	echo "Issues:"
	for issue in "${ISSUES[@]}"; do
		echo "  - $issue"
	done
	echo "Per-test logs kept in $FAILED_LOG_DIR"
	exit 1
fi
echo "All $PASS tests passed."
