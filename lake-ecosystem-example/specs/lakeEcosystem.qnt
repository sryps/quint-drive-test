// -*- mode: Bluespec; -*-

/// Lake Ecosystem Model
///
/// Models a freshwater lake ecosystem with three trophic levels:
/// algae (primary producers), minnows (primary consumers), and
/// walleye (apex predators), plus environmental factors.
///
/// Key emergent behaviors:
///   - Predator-prey oscillations (Lotka-Volterra dynamics)
///   - Algae blooms from nutrient excess
///   - Eutrophication feedback loop (bloom → die-off → O2 crash → fish kill)
///   - Seasonal forcing (temperature, growth rates, spawning windows)
///
/// All quantities are scaled ×10 to avoid decimals (e.g. 120 = 12.0°C).
module lakeEcosystem {

  // =====================================================
  // TYPES
  // =====================================================

  /// Season of the year
  type Season =
    | Spring
    | Summer
    | Autumn
    | Winter

  /// Ecosystem health (derived, not stored in state)
  type EcosystemHealth =
    | Healthy
    | Stressed
    | AlgaeBloom
    | OxygenCrisis
    | Collapsed

  /// Labels for each transition, enabling deterministic trace replay.
  /// Parameterized variants carry the nondeterministic choice.
  type ActionLabel =
    | NoAction
    | AdvanceSeason
    | AlgaeGrow
    | MinnowGraze(int)
    | WalleyeHunt(int)
    | MinnowSpawn
    | WalleyeSpawn
    | NutrientRunoff(int)
    | Decompose
    | OxygenDynamics
    | WinterDieOff
    | FishKill
    | NutrientRecycle

  /// Type aliases (all scaled ×10)
  type Biomass = int
  type Population = int
  type Nutrient = int
  type Oxygen = int
  type Temperature = int

  /// Full ecosystem state
  type State = {
    algaeBiomass: Biomass,
    minnowPop: Population,
    walleyePop: Population,
    dissolvedOxygen: Oxygen,
    nutrients: Nutrient,
    season: Season,
    waterTemp: Temperature,
    dayInSeason: int,
    detritus: Biomass,
    totalFishKills: int,
    totalAlgaeBlooms: int,
  }

  // =====================================================
  // CONSTANTS
  // =====================================================

  /// Module parameters (initial conditions)
  const INITIAL_ALGAE: Biomass
  const INITIAL_MINNOWS: Population
  const INITIAL_WALLEYE: Population
  const INITIAL_NUTRIENTS: Nutrient
  const INITIAL_OXYGEN: Oxygen

  /// Carrying capacities
  pure val MAX_ALGAE = 5000
  pure val MAX_MINNOWS = 1000
  pure val MAX_WALLEYE = 150
  pure val MAX_OXYGEN = 140       // 14.0 mg/L
  pure val MAX_NUTRIENTS = 1000
  pure val MAX_DETRITUS = 3000

  /// Oxygen thresholds (tenths of mg/L)
  pure val OXYGEN_STRESS = 50     // 5.0 mg/L — fish become stressed
  pure val OXYGEN_LETHAL = 20     // 2.0 mg/L — fish kills begin

  /// Algae bloom threshold
  pure val ALGAE_BLOOM_THRESHOLD = 3000

  /// Season temperatures (tenths of °C)
  pure val SPRING_TEMP = 120      // 12.0°C
  pure val SUMMER_TEMP = 240      // 24.0°C
  pure val AUTUMN_TEMP = 100      // 10.0°C
  pure val WINTER_TEMP = 30       //  3.0°C

  /// Season growth multipliers (percentage, 100 = 1.0×)
  pure val SPRING_GROWTH = 120    // 1.2×
  pure val SUMMER_GROWTH = 150    // 1.5×
  pure val AUTUMN_GROWTH = 60     // 0.6×
  pure val WINTER_GROWTH = 10     // 0.1×

  /// Steps per season before season advances
  pure val DAYS_PER_SEASON = 5

  /// Nondeterministic choice sets
  pure val RUNOFF_AMOUNTS: Set[int] = Set(20, 50, 100, 150, 200)
  pure val GRAZE_EFFORTS: Set[int] = Set(1, 2, 3, 4, 5)
  pure val HUNT_EFFORTS: Set[int] = Set(1, 2, 3)

  // =====================================================
  // HELPER PURE FUNCTIONS
  // =====================================================

  /// Clamp a value to [lo, hi]
  pure def clamp(value: int, lo: int, hi: int): int = {
    if (value < lo) lo
    else if (value > hi) hi
    else value
  }

  /// Next season in cycle
  pure def nextSeason(s: Season): Season = {
    match s {
      | Spring => Summer
      | Summer => Autumn
      | Autumn => Winter
      | Winter => Spring
    }
  }

  /// Temperature for a given season
  pure def seasonTemperature(s: Season): Temperature = {
    match s {
      | Spring => SPRING_TEMP
      | Summer => SUMMER_TEMP
      | Autumn => AUTUMN_TEMP
      | Winter => WINTER_TEMP
    }
  }

  /// Growth multiplier for a given season (percentage)
  pure def seasonGrowthMultiplier(s: Season): int = {
    match s {
      | Spring => SPRING_GROWTH
      | Summer => SUMMER_GROWTH
      | Autumn => AUTUMN_GROWTH
      | Winter => WINTER_GROWTH
    }
  }

  /// Oxygen saturation capacity — cold water holds more O2
  /// Returns max O2 in tenths of mg/L based on temperature
  pure def oxygenSaturation(temp: Temperature): Oxygen = {
    // Simplified: at 0°C → 140 (14.0 mg/L), decreases ~0.3 per °C
    // temp is in tenths, so per unit of temp: 140 - temp * 3 / 10
    val sat = 140 - (temp * 3) / 100
    clamp(sat, 60, 140)
  }

  /// Classify ecosystem health from current state (derived, not stored)
  pure def classifyHealth(state: State): EcosystemHealth = {
    if (state.minnowPop == 0 and state.walleyePop == 0) Collapsed
    else if (state.dissolvedOxygen <= OXYGEN_LETHAL) OxygenCrisis
    else if (state.algaeBiomass >= ALGAE_BLOOM_THRESHOLD) AlgaeBloom
    else if (state.dissolvedOxygen <= OXYGEN_STRESS) Stressed
    else Healthy
  }

  // =====================================================
  // TRANSITION PURE FUNCTIONS
  // =====================================================

  /// 1. Advance to next season when day counter reaches limit
  pure def advanceSeason(
    state: State
  ): { success: bool, newState: State } = {
    if (state.dayInSeason < DAYS_PER_SEASON - 1) {
      { success: false, newState: state }
    } else {
      val ns = nextSeason(state.season)
      { success: true, newState: {
        ...state,
        season: ns,
        waterTemp: seasonTemperature(ns),
        dayInSeason: 0,
      }}
    }
  }

  /// 2. Algae photosynthetic growth — nutrient-limited, light-limited at high density
  pure def algaeGrow(
    state: State
  ): { success: bool, newState: State } = {
    if (state.nutrients <= 0) {
      { success: false, newState: state }
    } else {
      // Base growth: 10% of current biomass
      val baseGrowth = state.algaeBiomass / 10
      // Season multiplier
      val seasonalGrowth = (baseGrowth * seasonGrowthMultiplier(state.season)) / 100
      // Nutrient limitation: growth capped by available nutrients × 2
      val nutrientLimited = if (seasonalGrowth > state.nutrients * 2) state.nutrients * 2
                            else seasonalGrowth
      // Self-shading: reduce growth when approaching carrying capacity
      val capacityFraction = (MAX_ALGAE - state.algaeBiomass)
      val lightLimited = if (capacityFraction <= 0) 0
                         else (nutrientLimited * capacityFraction) / MAX_ALGAE
      // Minimum growth of 1 if nutrients exist and below capacity
      val growth = if (lightLimited <= 0 and state.algaeBiomass < MAX_ALGAE) 1
                   else lightLimited
      // Nutrient uptake: algae consume nutrients proportional to growth
      val nutrientUptake = growth / 2
      val newAlgae = clamp(state.algaeBiomass + growth, 0, MAX_ALGAE)
      // Track bloom events: count when algae crosses threshold
      val newBlooms = if (newAlgae >= ALGAE_BLOOM_THRESHOLD and state.algaeBiomass < ALGAE_BLOOM_THRESHOLD)
        state.totalAlgaeBlooms + 1
        else state.totalAlgaeBlooms
      { success: true, newState: {
        ...state,
        algaeBiomass: newAlgae,
        nutrients: clamp(state.nutrients - nutrientUptake, 0, MAX_NUTRIENTS),
        dayInSeason: state.dayInSeason + 1,
        totalAlgaeBlooms: newBlooms,
      }}
    }
  }

  /// 3. Minnows graze on algae
  pure def minnowGraze(
    state: State,
    effort: int
  ): { success: bool, newState: State } = {
    if (state.minnowPop <= 0 or state.algaeBiomass <= 0) {
      { success: false, newState: state }
    } else {
      // Grazing proportional to population × effort
      val grazed = (state.minnowPop * effort) / 10
      val actualGrazed = if (grazed > state.algaeBiomass) state.algaeBiomass else grazed
      // Starvation: if algae per minnow is very low, minnows die
      val algaePerFish = state.algaeBiomass / state.minnowPop
      val starvationLoss = if (algaePerFish < 2) state.minnowPop / 10 else 0
      { success: true, newState: {
        ...state,
        algaeBiomass: clamp(state.algaeBiomass - actualGrazed, 0, MAX_ALGAE),
        minnowPop: clamp(state.minnowPop - starvationLoss, 0, MAX_MINNOWS),
        detritus: clamp(state.detritus + starvationLoss, 0, MAX_DETRITUS),
        dayInSeason: state.dayInSeason + 1,
      }}
    }
  }

  /// 4. Walleye hunt minnows
  pure def walleyeHunt(
    state: State,
    effort: int
  ): { success: bool, newState: State } = {
    if (state.walleyePop <= 0 or state.minnowPop <= 0) {
      { success: false, newState: state }
    } else {
      // Catch proportional to walleye population × effort
      val caught = (state.walleyePop * effort) / 5
      val actualCaught = if (caught > state.minnowPop) state.minnowPop else caught
      // Walleye starvation: if minnows per walleye is very low
      val preyPerPred = state.minnowPop / state.walleyePop
      val starvationLoss = if (preyPerPred < 3) state.walleyePop / 10 else 0
      { success: true, newState: {
        ...state,
        minnowPop: clamp(state.minnowPop - actualCaught, 0, MAX_MINNOWS),
        walleyePop: clamp(state.walleyePop - starvationLoss, 0, MAX_WALLEYE),
        detritus: clamp(state.detritus + starvationLoss, 0, MAX_DETRITUS),
        dayInSeason: state.dayInSeason + 1,
      }}
    }
  }

  /// 5. Minnow spawning — Spring/Summer, sufficient population, adequate O2
  pure def minnowSpawn(
    state: State
  ): { success: bool, newState: State } = {
    if (not(state.season == Spring or state.season == Summer)) {
      { success: false, newState: state }
    } else if (state.minnowPop < 10 or state.dissolvedOxygen < OXYGEN_STRESS) {
      { success: false, newState: state }
    } else {
      // +10% population
      val newFish = state.minnowPop / 10
      val spawn = if (newFish < 1) 1 else newFish
      { success: true, newState: {
        ...state,
        minnowPop: clamp(state.minnowPop + spawn, 0, MAX_MINNOWS),
        dayInSeason: state.dayInSeason + 1,
      }}
    }
  }

  /// 6. Walleye spawning — Spring only, sufficient population, right temp, adequate O2
  pure def walleyeSpawn(
    state: State
  ): { success: bool, newState: State } = {
    if (state.season != Spring) {
      { success: false, newState: state }
    } else if (state.walleyePop < 4 or state.dissolvedOxygen < OXYGEN_STRESS) {
      { success: false, newState: state }
    } else if (state.waterTemp < 60 or state.waterTemp > 150) {
      // Walleye spawn at 6.0-15.0°C
      { success: false, newState: state }
    } else {
      // +5% population, minimum 1
      val newFish = state.walleyePop / 20
      val spawn = if (newFish < 1) 1 else newFish
      { success: true, newState: {
        ...state,
        walleyePop: clamp(state.walleyePop + spawn, 0, MAX_WALLEYE),
        dayInSeason: state.dayInSeason + 1,
      }}
    }
  }

  /// 7. Nutrient runoff — external phosphorus input (Spring/Summer)
  pure def nutrientRunoff(
    state: State,
    amount: int
  ): { success: bool, newState: State } = {
    if (not(state.season == Spring or state.season == Summer)) {
      { success: false, newState: state }
    } else {
      { success: true, newState: {
        ...state,
        nutrients: clamp(state.nutrients + amount, 0, MAX_NUTRIENTS),
        dayInSeason: state.dayInSeason + 1,
      }}
    }
  }

  /// 8. Decomposition — detritus breaks down, releasing nutrients and consuming O2
  pure def decompose(
    state: State
  ): { success: bool, newState: State } = {
    if (state.detritus <= 0) {
      { success: false, newState: state }
    } else {
      // 20% of detritus decomposes per step
      val decomposed = state.detritus / 5
      val actualDecomposed = if (decomposed < 1) 1 else decomposed
      // Releases nutrients
      val nutrientRelease = actualDecomposed / 2
      // Consumes oxygen (bacterial respiration)
      val oxygenConsumed = actualDecomposed / 3
      { success: true, newState: {
        ...state,
        detritus: clamp(state.detritus - actualDecomposed, 0, MAX_DETRITUS),
        nutrients: clamp(state.nutrients + nutrientRelease, 0, MAX_NUTRIENTS),
        dissolvedOxygen: clamp(state.dissolvedOxygen - oxygenConsumed, 0, MAX_OXYGEN),
        dayInSeason: state.dayInSeason + 1,
      }}
    }
  }

  /// 9. Oxygen dynamics — photosynthesis, surface exchange, respiration (always enabled)
  pure def oxygenDynamics(
    state: State
  ): { success: bool, newState: State } = {
    // Photosynthesis: algae produce O2
    val photosynthesis = state.algaeBiomass / 50
    // Surface exchange: O2 diffuses toward saturation
    val saturation = oxygenSaturation(state.waterTemp)
    val exchangeRate = (saturation - state.dissolvedOxygen) / 5
    // Respiration: fish and bacteria consume O2
    val fishRespiration = (state.minnowPop + state.walleyePop * 3) / 20
    val bacterialRespiration = state.detritus / 10
    val totalRespiration = fishRespiration + bacterialRespiration
    // Net change
    val netChange = photosynthesis + exchangeRate - totalRespiration
    { success: true, newState: {
      ...state,
      dissolvedOxygen: clamp(state.dissolvedOxygen + netChange, 0, MAX_OXYGEN),
      dayInSeason: state.dayInSeason + 1,
    }}
  }

  /// 10. Winter die-off — seasonal population reduction
  pure def winterDieOff(
    state: State
  ): { success: bool, newState: State } = {
    if (state.season != Winter) {
      { success: false, newState: state }
    } else {
      // Algae -30%, minnows -10%, walleye -5%
      val algaeLoss = (state.algaeBiomass * 30) / 100
      val minnowLoss = (state.minnowPop * 10) / 100
      val walleyeLoss = (state.walleyePop * 5) / 100
      val totalDeadMatter = algaeLoss + minnowLoss + walleyeLoss
      { success: true, newState: {
        ...state,
        algaeBiomass: clamp(state.algaeBiomass - algaeLoss, 0, MAX_ALGAE),
        minnowPop: clamp(state.minnowPop - minnowLoss, 0, MAX_MINNOWS),
        walleyePop: clamp(state.walleyePop - walleyeLoss, 0, MAX_WALLEYE),
        detritus: clamp(state.detritus + totalDeadMatter, 0, MAX_DETRITUS),
        dayInSeason: state.dayInSeason + 1,
      }}
    }
  }

  /// 11. Fish kill — O2 too low, fish die (eutrophication feedback loop!)
  pure def fishKill(
    state: State
  ): { success: bool, newState: State } = {
    if (state.dissolvedOxygen > OXYGEN_LETHAL) {
      { success: false, newState: state }
    } else if (state.minnowPop <= 0 and state.walleyePop <= 0) {
      { success: false, newState: state }
    } else {
      // Minnows -40%, walleye -30%
      val minnowLoss = (state.minnowPop * 40) / 100
      val walleyeLoss = (state.walleyePop * 30) / 100
      val deadFish = minnowLoss + walleyeLoss
      { success: true, newState: {
        ...state,
        minnowPop: clamp(state.minnowPop - minnowLoss, 0, MAX_MINNOWS),
        walleyePop: clamp(state.walleyePop - walleyeLoss, 0, MAX_WALLEYE),
        detritus: clamp(state.detritus + deadFish, 0, MAX_DETRITUS),
        totalFishKills: state.totalFishKills + 1,
        dayInSeason: state.dayInSeason + 1,
      }}
    }
  }

  /// 12. Nutrient recycling — sediment phosphorus release when water nutrients are low
  pure def nutrientRecycle(
    state: State
  ): { success: bool, newState: State } = {
    if (state.nutrients > 100 or state.detritus < 50) {
      { success: false, newState: state }
    } else {
      // Sediment release: 10% of detritus nutrients
      val release = state.detritus / 10
      val actualRelease = if (release < 1) 1 else release
      { success: true, newState: {
        ...state,
        nutrients: clamp(state.nutrients + actualRelease, 0, MAX_NUTRIENTS),
        detritus: clamp(state.detritus - actualRelease, 0, MAX_DETRITUS),
        dayInSeason: state.dayInSeason + 1,
      }}
    }
  }

  // =====================================================
  // STATE VARIABLES
  // =====================================================

  var algaeBiomass: Biomass
  var minnowPop: Population
  var walleyePop: Population
  var dissolvedOxygen: Oxygen
  var nutrients: Nutrient
  var season: Season
  var waterTemp: Temperature
  var dayInSeason: int
  var detritus: Biomass
  var totalFishKills: int
  var totalAlgaeBlooms: int
  var lastAction: ActionLabel

  /// Pack state variables into a State record
  val currentState: State = {
    algaeBiomass: algaeBiomass,
    minnowPop: minnowPop,
    walleyePop: walleyePop,
    dissolvedOxygen: dissolvedOxygen,
    nutrients: nutrients,
    season: season,
    waterTemp: waterTemp,
    dayInSeason: dayInSeason,
    detritus: detritus,
    totalFishKills: totalFishKills,
    totalAlgaeBlooms: totalAlgaeBlooms,
  }

  /// Unpack a State record into state variables
  action setState(s: State): bool = all {
    algaeBiomass' = s.algaeBiomass,
    minnowPop' = s.minnowPop,
    walleyePop' = s.walleyePop,
    dissolvedOxygen' = s.dissolvedOxygen,
    nutrients' = s.nutrients,
    season' = s.season,
    waterTemp' = s.waterTemp,
    dayInSeason' = s.dayInSeason,
    detritus' = s.detritus,
    totalFishKills' = s.totalFishKills,
    totalAlgaeBlooms' = s.totalAlgaeBlooms,
  }

  action unchanged_all = all {
    setState(currentState),
    lastAction' = lastAction,
  }

  // =====================================================
  // INVARIANTS (Safety Properties)
  // =====================================================

  /// All populations are non-negative
  val populationsNonNegative = and {
    algaeBiomass >= 0,
    minnowPop >= 0,
    walleyePop >= 0,
  }

  /// Dissolved oxygen is non-negative
  val oxygenNonNegative = dissolvedOxygen >= 0

  /// Nutrients are non-negative
  val nutrientsNonNegative = nutrients >= 0

  /// Populations within carrying capacity
  val withinCarryingCapacity = and {
    algaeBiomass <= MAX_ALGAE,
    minnowPop <= MAX_MINNOWS,
    walleyePop <= MAX_WALLEYE,
  }

  /// Oxygen within bounds
  val oxygenWithinBounds = dissolvedOxygen <= MAX_OXYGEN

  /// Nutrients within bounds
  val nutrientsWithinBounds = nutrients <= MAX_NUTRIENTS

  /// Detritus within bounds
  val detritusWithinBounds = detritus >= 0 and detritus <= MAX_DETRITUS

  /// Temperature non-negative
  val temperatureNonNegative = waterTemp >= 0

  /// Combined safety invariant
  val safetyInvariant = and {
    populationsNonNegative,
    oxygenNonNegative,
    nutrientsNonNegative,
    withinCarryingCapacity,
    oxygenWithinBounds,
    nutrientsWithinBounds,
    detritusWithinBounds,
    temperatureNonNegative,
  }

  // =====================================================
  // ACTIONS - Thin wrappers calling pure functions
  // =====================================================

  action init = all {
    algaeBiomass' = INITIAL_ALGAE,
    minnowPop' = INITIAL_MINNOWS,
    walleyePop' = INITIAL_WALLEYE,
    dissolvedOxygen' = INITIAL_OXYGEN,
    nutrients' = INITIAL_NUTRIENTS,
    season' = Spring,
    waterTemp' = SPRING_TEMP,
    dayInSeason' = 0,
    detritus' = 0,
    totalFishKills' = 0,
    totalAlgaeBlooms' = 0,
    lastAction' = NoAction,
  }

  action doAdvanceSeason: bool = {
    val result = advanceSeason(currentState)
    all { result.success, setState(result.newState), lastAction' = AdvanceSeason }
  }

  action doAlgaeGrow: bool = {
    val result = algaeGrow(currentState)
    all { result.success, setState(result.newState), lastAction' = AlgaeGrow }
  }

  action doMinnowGraze: bool = {
    nondet effort = GRAZE_EFFORTS.oneOf()
    val result = minnowGraze(currentState, effort)
    all { result.success, setState(result.newState), lastAction' = MinnowGraze(effort) }
  }

  action doWalleyeHunt: bool = {
    nondet effort = HUNT_EFFORTS.oneOf()
    val result = walleyeHunt(currentState, effort)
    all { result.success, setState(result.newState), lastAction' = WalleyeHunt(effort) }
  }

  action doMinnowSpawn: bool = {
    val result = minnowSpawn(currentState)
    all { result.success, setState(result.newState), lastAction' = MinnowSpawn }
  }

  action doWalleyeSpawn: bool = {
    val result = walleyeSpawn(currentState)
    all { result.success, setState(result.newState), lastAction' = WalleyeSpawn }
  }

  action doNutrientRunoff: bool = {
    nondet amount = RUNOFF_AMOUNTS.oneOf()
    val result = nutrientRunoff(currentState, amount)
    all { result.success, setState(result.newState), lastAction' = NutrientRunoff(amount) }
  }

  action doDecompose: bool = {
    val result = decompose(currentState)
    all { result.success, setState(result.newState), lastAction' = Decompose }
  }

  action doOxygenDynamics: bool = {
    val result = oxygenDynamics(currentState)
    all { result.success, setState(result.newState), lastAction' = OxygenDynamics }
  }

  action doWinterDieOff: bool = {
    val result = winterDieOff(currentState)
    all { result.success, setState(result.newState), lastAction' = WinterDieOff }
  }

  action doFishKill: bool = {
    val result = fishKill(currentState)
    all { result.success, setState(result.newState), lastAction' = FishKill }
  }

  action doNutrientRecycle: bool = {
    val result = nutrientRecycle(currentState)
    all { result.success, setState(result.newState), lastAction' = NutrientRecycle }
  }

  /// Main step: nondeterministically choose one action
  action step = any {
    doAdvanceSeason,
    doAlgaeGrow,
    doMinnowGraze,
    doWalleyeHunt,
    doMinnowSpawn,
    doWalleyeSpawn,
    doNutrientRunoff,
    doDecompose,
    doOxygenDynamics,
    doWinterDieOff,
    doFishKill,
    doNutrientRecycle,
  }
}

/// Default instantiation with balanced initial conditions.
/// Use this module for direct simulation:
///   quint run specs/lakeEcosystem.qnt --main=lakeEcosystemDefault --invariant=safetyInvariant
module lakeEcosystemDefault {
  import lakeEcosystem(
    INITIAL_ALGAE = 500,
    INITIAL_MINNOWS = 200,
    INITIAL_WALLEYE = 30,
    INITIAL_NUTRIENTS = 300,
    INITIAL_OXYGEN = 90
  ).* from "./lakeEcosystem"
}
