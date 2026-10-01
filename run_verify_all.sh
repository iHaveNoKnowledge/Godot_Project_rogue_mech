#!/bin/bash
# CI-style aggregated verify runner for the Valkren Godot project.
#
# Runs every *verify*.tscn / *audit*.tscn under tests/ and test/ headless and
# classifies each result:
#   PASS          exit 0 + a "checks=N fails=0"-style summary (noise counted)
#   FAIL          exit != 0, summary with fails>0, or watchdog timeout
#   FALSE-PASS    exit 0 but NO summary line at all — the runner never finished
#                 its accounting (the mechless_register_verify failure mode:
#                 a script error aborts the checks yet the suite still "passes")
#   CRASH         native CrashHandlerException / segfault in the log
#
# Usage:
#   ./run_verify_all.sh [pattern ...]     # subset, e.g. ./run_verify_all.sh tests/mecha
# Options:
#   --timeout=N   per-scene watchdog seconds (default 120)
#
# Per-scene logs land in .godot/verify_logs/ (gitignored). Exit code is 0 only
# when every scene is an outright PASS.

set -u
GODOT_EXE="${GODOT_EXE:-/h/hack/project/godot/Godot_v4.6.2-stable_win64.exe}"
TIMEOUT_S=120
LOGROOT=".godot/verify_logs"
mkdir -p "$LOGROOT"

FILTER_ARGS=()
while [ $# -gt 0 ]; do
	case "$1" in
		--timeout=*) TIMEOUT_S="${1#--timeout=}"; shift ;;
		*) FILTER_ARGS+=("$1"); shift ;;
	esac
done

# Collect scenes: *verify* / *audit* .tscn under tests/ and test/.
SCENES=$(find tests test -name "*.tscn" 2>/dev/null | grep -Ei "verify|audit" | sort)
if [ ${#FILTER_ARGS[@]} -gt 0 ]; then
	PATTERN="(${FILTER_ARGS[*]})"
	SCENES=$(printf '%s\n' "$SCENES" | grep -E "$PATTERN" || true)
fi

TOTAL=0
PASS_LIST=()
FAIL_LIST=()
FALSE_LIST=()
CRASH_LIST=()

run_one() {
	local scene="$1"
	local safe
	safe=$(echo "$scene" | tr '/' '_')
	local log="$LOGROOT/$safe.log"
	local start end code noise summary
	start=$(date +%s)
	timeout --kill-after=10 "$TIMEOUT_S" "$GODOT_EXE" --headless "res://$scene" > "$log" 2>&1
	code=$?
	end=$(date +%s)
	local dur=$((end - start))
	TOTAL=$((TOTAL + 1))
	local label
	label=$(printf '%-70s %5ss' "$scene" "$dur")

	if grep -q "CrashHandlerException\|Segmentation fault" "$log" 2>/dev/null; then
		CRASH_LIST+=("$label")
		echo "CRASH    $label"
		return
	fi
	if [ "$code" -ne 0 ]; then
		FAIL_LIST+=("$label")
		echo "FAIL     $label"
		return
	fi
	local summary=""
	summary=$(grep -oiE "checks=[0-9]+[[:space:]]+fails=[0-9]+" "$log" 2>/dev/null | tail -1)
	if [ -z "$summary" ]; then
		# Count-bearing success footers of other harness dialects:
		#   "Checks=15, Fails=0" / "=== RESULT: 28 checks, 0 failures ==="
		#   "=== VERIFICATION COMPLETE: 71 checks, 0 failures ==="
		#   "Passed: 518 | Failed: 0" / "=== RESULTS: 53/53 passed (0 failed) ==="
		if grep -qiE "checks=[0-9]+[[:space:]]*,[[:space:]]*fails=0" "$log" 2>/dev/null \
			|| grep -qiE "checks=[0-9]+[[:space:]]*,[[:space:]]*0 failures" "$log" 2>/dev/null \
			|| grep -qiE "checks=[0-9]+[[:space:]]+passed[[:space:]]+with[[:space:]]+0 failures" "$log" 2>/dev/null \
			|| grep -qiE "[0-9]+[[:space:]]+checks[[:space:]]+passed" "$log" 2>/dev/null \
			|| grep -qiE "passed:[[:space:]]*[0-9]+[[:space:]]*\|[[:space:]]*failed:[[:space:]]*0" "$log" 2>/dev/null \
			|| grep -qiE "results?:[[:space:]]*[0-9]+/[0-9]+ passed[[:space:]]*\(0 failed\)" "$log" 2>/dev/null \
			|| grep -qiE "fails=[[:space:]]*0([^0-9]|$)" "$log" 2>/dev/null; then
			summary="dialect footer: 0 failures"
		else
			# Equal-ratio banner: "ALL ... CHECKS PASSED: 30/30"
			local ratio a b
			ratio=$(grep -oiE "PASSED:[[:space:]]*[0-9]+/[0-9]+" "$log" 2>/dev/null | tail -1)
			if [ -n "$ratio" ]; then
				a=${ratio##*PASSED: }; a=${a%%/*}; b=${ratio##*/}
				[ "$a" = "$b" ] && summary="dialect footer: $ratio"
			fi
		fi
	fi
	if [ -z "$summary" ]; then
		# Harness dialects without a checks= summary:
		#  1. legacy marker "--- ALL TESTS PASSED SUCCESSFULLY! ---"
		#  2. per-suite "*SUMMARY*" banner with PASS:/[PASS] lines
		# All count as a run ONLY when assertion-pass lines back them up AND no
		# assertion-failure line exists; a success banner with zero checks is
		# exactly the abort/false-pass mode this runner exists to catch.
		local pass_lines fail_lines
		pass_lines=$(grep -cE "PASS: |OK: |\[PASS\]" "$log" 2>/dev/null || true)
		# grep -c prints "0" (and exits 1) when nothing matches, so an
		# "|| echo 0" here would yield "0\n0" and kill the whole runner
		# with an arithmetic syntax error — capture and default instead.
		local check_lines
		check_lines=$(LC_ALL=C grep -c $'\xe2\x9c' "$log" 2>/dev/null)
		check_lines=${check_lines:-0}
		pass_lines=$(( pass_lines + check_lines ))
		fail_lines=$(grep -cE "FAIL: |FAILED: |ASSERTION FAILED|\[FAIL\]|✘|[1-9][0-9]* failures|[1-9][0-9]* failed" "$log" 2>/dev/null || true)
		if [ "${pass_lines:-0}" -gt 0 ] && [ "${fail_lines:-0}" -eq 0 ] \
			&& { grep -qiE "TESTS? PASSED|_SUCCESS|ALL_[A-Z_]*PASSED|SUMMARY|RESULTS?:|COMPLETED:|FINISHED" "$log" 2>/dev/null; }; then
			summary="dialect: ${pass_lines} asserts, fails=0"
		else
			FALSE_LIST+=("$label   (exit 0 without any summary — checks never ran to completion)")
			echo "FPASS?   $label"
			return
		fi
	fi
	# Dialect summaries end in "0 failures" or an equal-ratio "PASSED: X/X"
	# — accept them here too, otherwise the branches above set the summary
	# and this gate immediately rejects it (bogus FAILs).
	if ! echo "$summary" | grep -qiE "fails=0" \
		&& ! echo "$summary" | grep -qE "0 failures|PASSED: [0-9]+/[0-9]+"; then
		FAIL_LIST+=("$label   ($summary)")
		echo "FAIL     $label"
		return
	fi
	noise=$(grep -c "SCRIPT ERROR" "$log" 2>/dev/null || true)
	if [ "${noise:-0}" -gt 0 ]; then
		PASS_LIST+=("$label   ($summary, noisy: $noise script errors)")
		echo "PASS*    $label   (noisy: $noise script errors)"
	else
		PASS_LIST+=("$label   ($summary)")
		echo "PASS     $label"
	fi
}

# Warm the import cache once so first-run re-imports don't pollute results.
"$GODOT_EXE" --headless --import > "$LOGROOT/_import.log" 2>&1

for scene in $SCENES; do
	run_one "$scene"
done

echo
echo "==================== AGGREGATED VERIFY REPORT ===================="
echo "Scenes run : $TOTAL"
echo "PASS       : ${#PASS_LIST[@]}"
echo "FAIL       : ${#FAIL_LIST[@]}"
echo "FALSE-PASS : ${#FALSE_LIST[@]}"
echo "CRASH      : ${#CRASH_LIST[@]}"
if [ ${#FAIL_LIST[@]} -gt 0 ]; then
	echo "---- failing scenes ----"
	printf '  %s\n' "${FAIL_LIST[@]}"
fi
if [ ${#FALSE_LIST[@]} -gt 0 ]; then
	echo "---- false-pass suspects (exit 0, no summary) ----"
	printf '  %s\n' "${FALSE_LIST[@]}"
fi
if [ ${#CRASH_LIST[@]} -gt 0 ]; then
	echo "---- crashes ----"
	printf '  %s\n' "${CRASH_LIST[@]}"
fi
if [ ${#FAIL_LIST[@]} -gt 0 ] || [ ${#FALSE_LIST[@]} -gt 0 ] || [ ${#CRASH_LIST[@]} -gt 0 ]; then
	exit 1
fi
exit 0
