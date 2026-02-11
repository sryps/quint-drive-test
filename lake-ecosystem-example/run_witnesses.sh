#!/usr/bin/env bash
set -euo pipefail

SPEC="specs/lakeEcosystem_witnesses.qnt"
MAIN="lakeEcosystem_witnesses"
MAX_SAMPLES=10000

declare -A WITNESSES=(
  # Liveness witnesses
  [canReachAlgaeBloom]=200
  [canReachFishKill]=100
  [canCompleteSeason]=100
  [canRecoverFromStress]=100
  [canReachEutrophication]=200
  # Season witnesses
  [canReachSpring]=100
  [canReachSummer]=100
  [canReachAutumn]=100
  [canReachWinter]=100
  # Health state witnesses
  [canReachHealthy]=100
  [canReachStressed]=100
  [canReachAlgaeBloomHealth]=200
  [canReachOxygenCrisis]=100
  # Ecological event witnesses
  [canReachMinnowSpawn]=100
  [canReachWalleyeSpawn]=100
  [canReachDetritus]=100
  [canReachLowOxygen]=100
  [canReachHighNutrients]=100
  [canReachNutrientDepletion]=100
  [canReachDecomposition]=100
  # Causal chain witnesses
  [canSeeAlgaeKillWalleye]=200
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
