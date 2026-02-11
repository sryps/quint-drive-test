#!/usr/bin/env bash
set -euo pipefail

SPEC="specs/insulinPump_witnesses.qnt"
MAIN="insulinPump_witnesses"
MAX_SAMPLES=10000

declare -A WITNESSES=(
  # Liveness witnesses
  [canCompleteBolusDelivery]=100
  [canRecoverFromAlarm]=100
  [canResumeFromSuspension]=100
  [canDeliverMultipleBoluses]=200
  [canReachAlarmThenDeliver]=100
  # Reachability witnesses – Pump Modes
  [canReachMonitoring]=100
  [canReachCalculatingDose]=100
  [canReachDelivering]=100
  [canReachSuspended]=100
  [canReachAlarmActive]=100
  # Reachability witnesses – Alarm Conditions
  [canTriggerLowReservoir]=100
  [canTriggerHighGlucose]=100
  [canTriggerLowGlucose]=100
  [canTriggerOcclusion]=100
  [canTriggerMaxDoseExceeded]=100
  # Reachability witnesses – Configuration
  [canSetBasalRate]=100
  # Type variant witnesses
  [canReachIdle]=100
  [canTriggerEmptyReservoir]=100
  [canTriggerHardwareFault]=100
  [canReachNoDelivery]=100
  [canReachBasalDelivery]=100
  [canReachBolusDelivery]=100
  [canReachAlarmSeverityCritical]=100
)

cd "$(dirname "$0")"

passed=0
failed=0
failures=()

for witness in "${!WITNESSES[@]}"; do
  max_steps=${WITNESSES[$witness]}
  output=$(quint run "$SPEC" \
    --main="$MAIN" \
    --invariant="$witness" \
    --max-steps="$max_steps" \
    --max-samples="$MAX_SAMPLES" 2>&1) || true

  if echo "$output" | grep -q '\[violation\]'; then
    echo "PASS: $witness ($max_steps steps)"
    passed=$((passed + 1))
  else
    echo "FAIL: $witness ($max_steps steps)"
    failed=$((failed + 1))
    failures+=("$witness")
  fi
done

echo ""
echo "Results: $passed passed, $failed failed out of ${#WITNESSES[@]}"
if [ $failed -gt 0 ]; then
  echo "Failures: ${failures[*]}"
  exit 1
fi
