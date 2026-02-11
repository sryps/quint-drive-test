// -*- mode: Bluespec; -*-

/// Insulin Pump State Machine
///
/// Models a safety-critical insulin pump for diabetic patients.
/// Covers the full pump lifecycle: idle, monitoring glucose,
/// calculating dose, delivering insulin, alarm states, and error handling.
///
/// Key safety properties:
///   - Max single bolus dose is never exceeded
///   - Delivery only occurs when reservoir has sufficient insulin
///   - Alarms halt delivery and require acknowledgment
///   - Occlusion detection stops delivery immediately
module insulinPump {

  // =====================================================
  // TYPES
  // =====================================================

  /// Pump operating mode
  type PumpMode =
    | Idle
    | Monitoring
    | CalculatingDose
    | Delivering
    | Suspended
    | AlarmActive

  /// Alarm severity levels
  type AlarmSeverity =
    | Advisory
    | Alert
    | Critical

  /// Specific alarm conditions
  type AlarmCondition =
    | NoAlarm
    | LowReservoir
    | EmptyReservoir
    | Occlusion
    | HighGlucose
    | LowGlucose
    | HardwareFault
    | MaxDoseExceeded

  /// Type of insulin delivery
  type DeliveryType =
    | NoDelivery
    | BasalDelivery
    | BolusDelivery

  /// A glucose reading in mg/dL (modeled as int for simplicity)
  type GlucoseLevel = int

  /// Insulin amount in units (scaled by 100 to avoid decimals, e.g. 150 = 1.50 units)
  type InsulinUnits = int

  /// Labels for each transition, enabling deterministic trace replay.
  /// Parameterized variants carry the nondeterministic choice so traces are replayable.
  type ActionLabel =
    | NoAction
    | StartMonitoring
    | ProcessGlucose(GlucoseLevel)
    | RequestBolus(InsulinUnits)
    | ConfirmDelivery
    | DeliverIncrement
    | HandleOcclusion
    | CancelDelivery
    | AcknowledgeAlarm
    | SuspendPump
    | ResumePump
    | StartBasal(InsulinUnits)
    | DeliverBasal
    | DetectHardwareFault

  /// Full pump state
  type State = {
    mode: PumpMode,
    glucoseLevel: GlucoseLevel,
    reservoirLevel: InsulinUnits,
    currentDelivery: DeliveryType,
    deliveredAmount: InsulinUnits,
    pendingBolus: InsulinUnits,
    basalRate: InsulinUnits,
    alarmCondition: AlarmCondition,
    alarmAcknowledged: bool,
    totalDeliveredToday: InsulinUnits,
  }

  // =====================================================
  // CONSTANTS
  // =====================================================

  /// Glucose thresholds (mg/dL)
  pure val GLUCOSE_LOW = 70
  pure val GLUCOSE_HIGH = 180
  pure val GLUCOSE_CRITICAL_LOW = 54
  pure val GLUCOSE_CRITICAL_HIGH = 300
  pure val GLUCOSE_TARGET = 120

  /// Insulin limits (in hundredths of units)
  pure val MAX_SINGLE_BOLUS = 2500        // 25.00 units
  pure val MAX_DAILY_DOSE = 10000         // 100.00 units
  pure val LOW_RESERVOIR_THRESHOLD = 500  // 5.00 units remaining
  const INITIAL_RESERVOIR: InsulinUnits   // default: 20000 (200.00 units, full cartridge)

  /// Basal rate options (hundredths of units per step)
  pure val BASAL_RATES: Set[int] = Set(10, 25, 50, 75, 100) // 0.10 to 1.00 units

  /// Bolus amounts for nondeterministic selection
  pure val BOLUS_AMOUNTS: Set[int] = Set(50, 100, 200, 500, 1000, 2000, 2500, 3000)

  /// Glucose levels for nondeterministic selection
  pure val GLUCOSE_LEVELS: Set[int] = Set(40, 54, 70, 100, 120, 150, 180, 250, 300, 350)

  // =====================================================
  // PURE FUNCTIONS - All business logic here
  // =====================================================

  /// Determine alarm severity for a given condition
  pure def alarmSeverity(condition: AlarmCondition): AlarmSeverity = {
    match condition {
      | NoAlarm => Advisory
      | LowReservoir => Advisory
      | HighGlucose => Alert
      | LowGlucose => Alert
      | EmptyReservoir => Critical
      | Occlusion => Critical
      | HardwareFault => Critical
      | MaxDoseExceeded => Critical
    }
  }

  /// Check if an alarm condition is critical (requires immediate delivery stop)
  pure def isCriticalAlarm(condition: AlarmCondition): bool = {
    alarmSeverity(condition) == Critical
  }

  /// Detect alarm conditions from current state
  pure def detectAlarm(state: State): AlarmCondition = {
    if (state.reservoirLevel <= 0) EmptyReservoir
    else if (state.glucoseLevel <= GLUCOSE_CRITICAL_LOW) LowGlucose
    else if (state.glucoseLevel >= GLUCOSE_CRITICAL_HIGH) HighGlucose
    else if (state.reservoirLevel <= LOW_RESERVOIR_THRESHOLD) LowReservoir
    else NoAlarm
  }

  /// Calculate a correction bolus based on glucose level
  pure def calculateCorrectionBolus(glucose: GlucoseLevel): InsulinUnits = {
    if (glucose <= GLUCOSE_TARGET) 0
    else {
      // Simple linear correction: 1 unit per 50 mg/dL above target
      val excess = glucose - GLUCOSE_TARGET
      (excess * 100) / 50  // in hundredths of units
    }
  }

  /// Check if a bolus amount is safe to deliver
  pure def isBolusAllowed(
    state: State,
    bolusAmount: InsulinUnits
  ): { allowed: bool, reason: AlarmCondition } = {
    if (bolusAmount > MAX_SINGLE_BOLUS) {
      { allowed: false, reason: MaxDoseExceeded }
    } else if (bolusAmount > state.reservoirLevel) {
      { allowed: false, reason: EmptyReservoir }
    } else if (state.totalDeliveredToday + bolusAmount > MAX_DAILY_DOSE) {
      { allowed: false, reason: MaxDoseExceeded }
    } else {
      { allowed: true, reason: NoAlarm }
    }
  }

  /// Attempt to start monitoring from idle
  pure def startMonitoring(
    state: State
  ): { success: bool, newState: State } = {
    if (state.mode != Idle) {
      { success: false, newState: state }
    } else {
      { success: true, newState: { ...state, mode: Monitoring } }
    }
  }

  /// Process a new glucose reading
  pure def processGlucoseReading(
    state: State,
    reading: GlucoseLevel
  ): { success: bool, newState: State } = {
    if (state.mode != Monitoring and state.mode != Delivering) {
      { success: false, newState: state }
    } else {
      val updated = { ...state, glucoseLevel: reading }
      val alarm = detectAlarm(updated)
      if (alarm != NoAlarm and isCriticalAlarm(alarm)) {
        // Critical alarm: stop delivery and enter alarm mode
        { success: true, newState: {
          ...updated,
          mode: AlarmActive,
          alarmCondition: alarm,
          alarmAcknowledged: false,
          currentDelivery: NoDelivery,
          pendingBolus: 0,
        }}
      } else if (alarm != NoAlarm) {
        // Non-critical alarm: set alarm but continue
        { success: true, newState: { ...updated, alarmCondition: alarm } }
      } else {
        { success: true, newState: { ...updated, alarmCondition: NoAlarm } }
      }
    }
  }

  /// Request a bolus delivery
  pure def requestBolus(
    state: State,
    amount: InsulinUnits
  ): { success: bool, newState: State } = {
    if (state.mode != Monitoring) {
      { success: false, newState: state }
    } else {
      val check = isBolusAllowed(state, amount)
      if (not(check.allowed)) {
        { success: true, newState: {
          ...state,
          mode: AlarmActive,
          alarmCondition: check.reason,
          alarmAcknowledged: false,
          currentDelivery: NoDelivery,
        }}
      } else {
        { success: true, newState: {
          ...state,
          mode: CalculatingDose,
          pendingBolus: amount,
          currentDelivery: NoDelivery,
        }}
      }
    }
  }

  /// Confirm and begin delivering the pending bolus
  pure def confirmDelivery(
    state: State
  ): { success: bool, newState: State } = {
    if (state.mode != CalculatingDose or state.pendingBolus <= 0) {
      { success: false, newState: state }
    } else {
      { success: true, newState: {
        ...state,
        mode: Delivering,
        currentDelivery: BolusDelivery,
        deliveredAmount: 0,
      }}
    }
  }

  /// Deliver one increment of the pending bolus
  pure def deliverIncrement(
    state: State,
    amount: InsulinUnits
  ): { success: bool, newState: State } = {
    if (state.mode != Delivering) {
      { success: false, newState: state }
    } else if (state.reservoirLevel < amount) {
      // Cannot deliver: empty reservoir
      { success: true, newState: {
        ...state,
        mode: AlarmActive,
        alarmCondition: EmptyReservoir,
        alarmAcknowledged: false,
        currentDelivery: NoDelivery,
      }}
    } else {
      val newDelivered = state.deliveredAmount + amount
      val remaining = state.pendingBolus - newDelivered
      if (remaining <= 0) {
        // Delivery complete
        { success: true, newState: {
          ...state,
          mode: Monitoring,
          currentDelivery: NoDelivery,
          deliveredAmount: 0,
          pendingBolus: 0,
          reservoirLevel: state.reservoirLevel - amount,
          totalDeliveredToday: state.totalDeliveredToday + amount,
        }}
      } else {
        // Partial delivery, continue
        { success: true, newState: {
          ...state,
          deliveredAmount: newDelivered,
          reservoirLevel: state.reservoirLevel - amount,
          totalDeliveredToday: state.totalDeliveredToday + amount,
        }}
      }
    }
  }

  /// Handle an occlusion event during delivery
  pure def handleOcclusion(
    state: State
  ): { success: bool, newState: State } = {
    if (state.mode != Delivering) {
      { success: false, newState: state }
    } else {
      { success: true, newState: {
        ...state,
        mode: AlarmActive,
        alarmCondition: Occlusion,
        alarmAcknowledged: false,
        currentDelivery: NoDelivery,
      }}
    }
  }

  /// Cancel an in-progress bolus delivery
  pure def cancelDelivery(
    state: State
  ): { success: bool, newState: State } = {
    if (state.mode != Delivering and state.mode != CalculatingDose) {
      { success: false, newState: state }
    } else {
      { success: true, newState: {
        ...state,
        mode: Monitoring,
        currentDelivery: NoDelivery,
        pendingBolus: 0,
        deliveredAmount: 0,
      }}
    }
  }

  /// Acknowledge an alarm
  pure def acknowledgeAlarm(
    state: State
  ): { success: bool, newState: State } = {
    if (state.mode != AlarmActive) {
      { success: false, newState: state }
    } else {
      // After acknowledging, check if we can return to monitoring
      val canResume = match state.alarmCondition {
        | EmptyReservoir => false   // Cannot resume with no insulin
        | HardwareFault => false    // Cannot resume with hardware fault
        | Occlusion => false        // Needs physical intervention
        | _ => true
      }
      if (canResume) {
        { success: true, newState: {
          ...state,
          mode: Monitoring,
          alarmCondition: NoAlarm,
          alarmAcknowledged: true,
        }}
      } else {
        { success: true, newState: {
          ...state,
          mode: Suspended,
          alarmAcknowledged: true,
        }}
      }
    }
  }

  /// Suspend the pump (user-initiated)
  pure def suspendPump(
    state: State
  ): { success: bool, newState: State } = {
    if (state.mode == Suspended or state.mode == Idle) {
      { success: false, newState: state }
    } else {
      { success: true, newState: {
        ...state,
        mode: Suspended,
        currentDelivery: NoDelivery,
        pendingBolus: 0,
        deliveredAmount: 0,
      }}
    }
  }

  /// Resume from suspended state
  pure def resumePump(
    state: State
  ): { success: bool, newState: State } = {
    if (state.mode != Suspended) {
      { success: false, newState: state }
    } else if (state.reservoirLevel <= 0) {
      // Cannot resume with empty reservoir
      { success: false, newState: state }
    } else {
      { success: true, newState: {
        ...state,
        mode: Monitoring,
        alarmCondition: NoAlarm,
        alarmAcknowledged: false,
      }}
    }
  }

  /// Configure basal rate
  pure def startBasal(
    state: State,
    rate: InsulinUnits
  ): { success: bool, newState: State } = {
    if (state.mode != Monitoring) {
      { success: false, newState: state }
    } else {
      { success: true, newState: { ...state, basalRate: rate } }
    }
  }

  /// Deliver one basal increment (periodic background delivery)
  pure def deliverBasal(
    state: State
  ): { success: bool, newState: State } = {
    if (state.mode != Monitoring or state.basalRate <= 0) {
      { success: false, newState: state }
    } else if (state.reservoirLevel < state.basalRate) {
      // Not enough insulin for basal delivery
      { success: true, newState: {
        ...state,
        mode: AlarmActive,
        alarmCondition: EmptyReservoir,
        alarmAcknowledged: false,
        currentDelivery: NoDelivery,
      }}
    } else {
      { success: true, newState: {
        ...state,
        currentDelivery: BasalDelivery,
        reservoirLevel: state.reservoirLevel - state.basalRate,
        totalDeliveredToday: state.totalDeliveredToday + state.basalRate,
      }}
    }
  }

  /// Detect a hardware fault (nondeterministic — can occur in any active mode)
  pure def detectHardwareFault(
    state: State
  ): { success: bool, newState: State } = {
    if (state.mode == Idle or state.mode == AlarmActive) {
      { success: false, newState: state }
    } else {
      { success: true, newState: {
        ...state,
        mode: AlarmActive,
        alarmCondition: HardwareFault,
        alarmAcknowledged: false,
        currentDelivery: NoDelivery,
        pendingBolus: 0,
      }}
    }
  }

  // =====================================================
  // STATE VARIABLES
  // =====================================================

  var mode: PumpMode
  var glucoseLevel: GlucoseLevel
  var reservoirLevel: InsulinUnits
  var currentDelivery: DeliveryType
  var deliveredAmount: InsulinUnits
  var pendingBolus: InsulinUnits
  var basalRate: InsulinUnits
  var alarmCondition: AlarmCondition
  var alarmAcknowledged: bool
  var totalDeliveredToday: InsulinUnits
  var lastAction: ActionLabel

  /// Pack state variables into a State record
  val currentState: State = {
    mode: mode,
    glucoseLevel: glucoseLevel,
    reservoirLevel: reservoirLevel,
    currentDelivery: currentDelivery,
    deliveredAmount: deliveredAmount,
    pendingBolus: pendingBolus,
    basalRate: basalRate,
    alarmCondition: alarmCondition,
    alarmAcknowledged: alarmAcknowledged,
    totalDeliveredToday: totalDeliveredToday,
  }

  /// Unpack a State record into state variables
  action setState(s: State): bool = all {
    mode' = s.mode,
    glucoseLevel' = s.glucoseLevel,
    reservoirLevel' = s.reservoirLevel,
    currentDelivery' = s.currentDelivery,
    deliveredAmount' = s.deliveredAmount,
    pendingBolus' = s.pendingBolus,
    basalRate' = s.basalRate,
    alarmCondition' = s.alarmCondition,
    alarmAcknowledged' = s.alarmAcknowledged,
    totalDeliveredToday' = s.totalDeliveredToday,
  }

  action unchanged_all = all {
    setState(currentState),
    lastAction' = lastAction,
  }

  // =====================================================
  // INVARIANTS (Safety Properties)
  // =====================================================

  /// The reservoir level is never negative
  val reservoirNonNegative = reservoirLevel >= 0

  /// A single bolus never exceeds the max allowed
  val bolusWithinLimit = pendingBolus <= MAX_SINGLE_BOLUS

  /// Daily total delivery never exceeds the max
  val dailyDoseWithinLimit = totalDeliveredToday <= MAX_DAILY_DOSE

  /// Delivery only occurs in the correct mode
  val deliveryOnlyWhenDelivering = and {
    (currentDelivery == BolusDelivery) implies (mode == Delivering),
    (currentDelivery == BasalDelivery) implies (mode == Monitoring),
  }

  /// Critical alarms always halt delivery
  val criticalAlarmStopsDelivery =
    isCriticalAlarm(alarmCondition) implies (currentDelivery == NoDelivery)

  /// No delivery with empty reservoir
  val noDeliveryWhenEmpty =
    (reservoirLevel <= 0) implies (currentDelivery == NoDelivery)

  /// Combined safety invariant
  val safetyInvariant = and {
    reservoirNonNegative,
    bolusWithinLimit,
    dailyDoseWithinLimit,
    deliveryOnlyWhenDelivering,
    criticalAlarmStopsDelivery,
    noDeliveryWhenEmpty,
  }

  // =====================================================
  // ACTIONS - Thin wrappers calling pure functions
  // =====================================================

  action init = all {
    mode' = Idle,
    glucoseLevel' = GLUCOSE_TARGET,
    reservoirLevel' = INITIAL_RESERVOIR,
    currentDelivery' = NoDelivery,
    deliveredAmount' = 0,
    pendingBolus' = 0,
    basalRate' = 0,
    alarmCondition' = NoAlarm,
    alarmAcknowledged' = false,
    totalDeliveredToday' = 0,
    lastAction' = NoAction,
  }

  action doStartMonitoring: bool = {
    val result = startMonitoring(currentState)
    all { result.success, setState(result.newState), lastAction' = StartMonitoring }
  }

  action doProcessGlucose: bool = {
    nondet reading = GLUCOSE_LEVELS.oneOf()
    val result = processGlucoseReading(currentState, reading)
    all { result.success, setState(result.newState), lastAction' = ProcessGlucose(reading) }
  }

  action doRequestBolus: bool = {
    nondet amount = BOLUS_AMOUNTS.oneOf()
    val result = requestBolus(currentState, amount)
    all { result.success, setState(result.newState), lastAction' = RequestBolus(amount) }
  }

  action doConfirmDelivery: bool = {
    val result = confirmDelivery(currentState)
    all { result.success, setState(result.newState), lastAction' = ConfirmDelivery }
  }

  action doDeliverIncrement: bool = {
    // Deliver in increments of 0.10 units
    val result = deliverIncrement(currentState, 10)
    all { result.success, setState(result.newState), lastAction' = DeliverIncrement }
  }

  action doHandleOcclusion: bool = {
    val result = handleOcclusion(currentState)
    all { result.success, setState(result.newState), lastAction' = HandleOcclusion }
  }

  action doCancelDelivery: bool = {
    val result = cancelDelivery(currentState)
    all { result.success, setState(result.newState), lastAction' = CancelDelivery }
  }

  action doAcknowledgeAlarm: bool = {
    val result = acknowledgeAlarm(currentState)
    all { result.success, setState(result.newState), lastAction' = AcknowledgeAlarm }
  }

  action doSuspendPump: bool = {
    val result = suspendPump(currentState)
    all { result.success, setState(result.newState), lastAction' = SuspendPump }
  }

  action doResumePump: bool = {
    val result = resumePump(currentState)
    all { result.success, setState(result.newState), lastAction' = ResumePump }
  }

  action doStartBasal: bool = {
    nondet rate = BASAL_RATES.oneOf()
    val result = startBasal(currentState, rate)
    all { result.success, setState(result.newState), lastAction' = StartBasal(rate) }
  }

  action doDeliverBasal: bool = {
    val result = deliverBasal(currentState)
    all { result.success, setState(result.newState), lastAction' = DeliverBasal }
  }

  action doDetectHardwareFault: bool = {
    val result = detectHardwareFault(currentState)
    all { result.success, setState(result.newState), lastAction' = DetectHardwareFault }
  }

  /// Main step: nondeterministically choose one action
  action step = any {
    doStartMonitoring,
    doProcessGlucose,
    doRequestBolus,
    doConfirmDelivery,
    doDeliverIncrement,
    doHandleOcclusion,
    doCancelDelivery,
    doAcknowledgeAlarm,
    doSuspendPump,
    doResumePump,
    doStartBasal,
    doDeliverBasal,
    doDetectHardwareFault,
  }
}

/// Default instantiation with a full 200.00-unit cartridge.
/// Use this module for direct simulation:
///   quint run specs/insulinPump.qnt --main=insulinPumpDefault --invariant=safetyInvariant
module insulinPumpDefault {
  import insulinPump(INITIAL_RESERVOIR = 20000).* from "./insulinPump"
}
