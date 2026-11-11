#!/usr/bin/env bash
# Run one ExampleFlows test on the simulator in ../sim-id; xcodebuild can hang after the suite ends on
# Xcode 27.1, so it is stopped once the summary line appears.  usage: run.sh test1GuestPayment
set -u
cd "$(dirname "$0")"
ID=$(cat ../sim-id)
LOG=../ui-$1.log
xcodebuild test-without-building -project PaysheetUITests.xcodeproj -scheme PaysheetUITests -destination "id=$ID" \
  -derivedDataPath ../uitest-dd -collect-test-diagnostics never -only-testing:PaysheetUITests/ExampleFlows/$1 > "$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 360); do
  grep -q "Test Case .* \(passed\|failed\) (" "$LOG" 2>/dev/null && { sleep 2; break; }
  kill -0 $PID 2>/dev/null || break
  sleep 1
done
kill $PID 2>/dev/null
grep -E "Test Case .*(passed|failed)|error:" "$LOG" | cut -c1-400 | head -5
