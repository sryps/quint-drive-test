// -*- mode: Bluespec; -*-

// ============================================================
// WITNESS SCENARIOS - SANITY CHECKS FOR REACHABILITY
// ============================================================
//
// Purpose:
//   Witnesses verify that interesting scenarios are reachable
//   in the lake ecosystem specification. They serve as sanity
//   checks that the spec is not vacuous or overly constrained.
//
// How they work:
//   Each witness is a NEGATED condition used as an invariant.
//   Random simulation tries to VIOLATE the invariant.
//
//   Violation = scenario IS reachable (good!)
//   No violation = scenario may be UNREACHABLE (investigate!)
//
// Usage:
//   quint run specs/lakeEcosystem_witnesses.qnt \
//     --main=lakeEcosystem_witnesses \
//     --invariant=<witness_name> \
//     --max-steps=50 --max-samples=10000
//
// ============================================================
//
// WITNESS CATALOG
//
// Liveness Witnesses (5):
//   canReachAlgaeBloom         - Algae biomass crosses bloom threshold
//   canReachFishKill           - O2 crash triggers fish kill event
//   canCompleteSeason          - Season advances from one to next
//   canRecoverFromStress       - Ecosystem returns to Healthy after Stressed
//   canReachEutrophication     - Full feedback loop: bloom + fish kill
//
// Season Witnesses (4):
//   canReachSpring             - System reaches Spring
//   canReachSummer             - System reaches Summer
//   canReachAutumn             - System reaches Autumn
//   canReachWinter             - System reaches Winter
//
// Health State Witnesses (4):
//   canReachHealthy            - Ecosystem classified as Healthy
//   canReachStressed           - Ecosystem classified as Stressed
//   canReachAlgaeBloomHealth   - Ecosystem classified as AlgaeBloom
//   canReachOxygenCrisis       - Ecosystem classified as OxygenCrisis
//
// Ecological Event Witnesses (7):
//   canReachMinnowSpawn        - Minnows successfully spawn
//   canReachWalleyeSpawn       - Walleye successfully spawn
//   canReachDetritus           - Detritus accumulates in the lake
//   canReachLowOxygen          - Dissolved oxygen drops below stress threshold
//   canReachHighNutrients      - Nutrients rise above 500
//   canReachNutrientDepletion  - Nutrients drop near zero
//   canReachDecomposition      - Decomposition action fires
//
// ============================================================

module lakeEcosystem_witnesses {
  // Instantiate with eutrophic conditions (high nutrients=700)
  // for faster witness triggering of bloom/crisis scenarios.
  import lakeEcosystem(
    INITIAL_ALGAE = 500,
    INITIAL_MINNOWS = 200,
    INITIAL_WALLEYE = 30,
    INITIAL_NUTRIENTS = 700,
    INITIAL_OXYGEN = 90
  ).* from "./lakeEcosystem"

  // ──────────────────────────────────────────────────────────
  // Helper predicates
  // ──────────────────────────────────────────────────────────

  /// Current ecosystem health classification
  val health: EcosystemHealth = classifyHealth(currentState)

  // ──────────────────────────────────────────────────────────
  // LIVENESS WITNESSES
  // ──────────────────────────────────────────────────────────

  // Witness: Algae bloom occurs
  // Goal: Algae biomass reaches the bloom threshold (3000)
  // EXPECTED: Invariant VIOLATION (proves blooms can happen)
  val canReachAlgaeBloom: bool = not(algaeBiomass >= ALGAE_BLOOM_THRESHOLD)

  // Witness: Fish kill event occurs
  // Goal: O2 crashes low enough to trigger a fish kill
  // EXPECTED: Invariant VIOLATION (proves eutrophication feedback)
  val canReachFishKill: bool = not(totalFishKills > 0)

  // Witness: Season completes a full cycle
  // Goal: Season advances at least once
  // EXPECTED: Invariant VIOLATION
  val canCompleteSeason: bool = not(season == Summer)

  // Witness: Recovery from stress
  // Goal: After O2 drops below stress, ecosystem returns to Healthy
  // EXPECTED: Invariant VIOLATION
  val canRecoverFromStress: bool = not(
    health == Healthy and totalFishKills == 0 and detritus > 0
  )

  // Witness: Full eutrophication feedback loop
  // Goal: Algae bloom AND fish kill both occur in same run
  // EXPECTED: Invariant VIOLATION
  val canReachEutrophication: bool = not(
    totalAlgaeBlooms > 0 and totalFishKills > 0
  )

  // ──────────────────────────────────────────────────────────
  // SEASON WITNESSES
  // ──────────────────────────────────────────────────────────

  // Witness: Reach Spring (init starts in Spring, so trivially reachable)
  // EXPECTED: Invariant VIOLATION
  val canReachSpring: bool = not(season == Spring)

  // Witness: Reach Summer
  // EXPECTED: Invariant VIOLATION
  val canReachSummer: bool = not(season == Summer)

  // Witness: Reach Autumn
  // EXPECTED: Invariant VIOLATION
  val canReachAutumn: bool = not(season == Autumn)

  // Witness: Reach Winter
  // EXPECTED: Invariant VIOLATION
  val canReachWinter: bool = not(season == Winter)

  // ──────────────────────────────────────────────────────────
  // HEALTH STATE WITNESSES
  // ──────────────────────────────────────────────────────────

  // Witness: Healthy ecosystem
  // EXPECTED: Invariant VIOLATION
  val canReachHealthy: bool = not(health == Healthy)

  // Witness: Stressed ecosystem (low O2 but above lethal)
  // EXPECTED: Invariant VIOLATION
  val canReachStressed: bool = not(health == Stressed)

  // Witness: Algae bloom health state
  // EXPECTED: Invariant VIOLATION
  val canReachAlgaeBloomHealth: bool = not(health == AlgaeBloom)

  // Witness: Oxygen crisis
  // EXPECTED: Invariant VIOLATION
  val canReachOxygenCrisis: bool = not(health == OxygenCrisis)

  // ──────────────────────────────────────────────────────────
  // ECOLOGICAL EVENT WITNESSES
  // ──────────────────────────────────────────────────────────

  // Witness: Minnows successfully spawn
  // EXPECTED: Invariant VIOLATION
  val canReachMinnowSpawn: bool = not(
    minnowPop > 200 and season == Spring
  )

  // Witness: Walleye successfully spawn
  // EXPECTED: Invariant VIOLATION
  val canReachWalleyeSpawn: bool = not(
    walleyePop > 30 and season == Spring
  )

  // Witness: Detritus accumulates
  // EXPECTED: Invariant VIOLATION
  val canReachDetritus: bool = not(detritus > 50)

  // Witness: Dissolved oxygen drops below stress threshold
  // EXPECTED: Invariant VIOLATION
  val canReachLowOxygen: bool = not(dissolvedOxygen < OXYGEN_STRESS)

  // Witness: High nutrient loading
  // EXPECTED: Invariant VIOLATION
  val canReachHighNutrients: bool = not(nutrients > 500)

  // Witness: Nutrients nearly depleted (algae consumed them)
  // EXPECTED: Invariant VIOLATION
  val canReachNutrientDepletion: bool = not(nutrients < 20)

  // Witness: Decomposition occurs (detritus breaks down)
  // EXPECTED: Invariant VIOLATION
  val canReachDecomposition: bool = not(
    detritus > 0 and nutrients > 0 and lastAction == Decompose
  )

  // ──────────────────────────────────────────────────────────
  // CAUSAL CHAIN WITNESSES
  // ──────────────────────────────────────────────────────────

  // Witness: Algae overgrowth kills walleye
  // Goal: Algae bloom occurs, then O2 crashes, then walleye population
  //   drops below half its initial value via fish kill events.
  //   Validates the full eutrophication feedback loop hits apex predators.
  // EXPECTED: Invariant VIOLATION
  val canSeeAlgaeKillWalleye: bool = not(
    totalAlgaeBlooms > 0 and totalFishKills > 0 and walleyePop < 15
  )
}
