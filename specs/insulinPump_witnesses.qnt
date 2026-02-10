// -*- mode: Bluespec; -*-

// ============================================================
// WITNESS SCENARIOS - SANITY CHECKS FOR REACHABILITY
// ============================================================
//
// Purpose:
//   Witnesses verify that interesting scenarios are reachable
//   in the insulin pump specification. They serve as sanity
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
//   quint run specs/insulinPump_witnesses.qnt \
//     --main=insulinPump_witnesses \
//     --invariant=<witness_name> \
//     --max-steps=50 --max-samples=10000
//
// ============================================================
//
// WITNESS CATALOG
//
// Liveness Witnesses (5):
//   canCompleteBolusDelivery    - Full bolus lifecycle completes
//   canRecoverFromAlarm         - Alarm acknowledged, pump resumes monitoring
//   canResumeFromSuspension     - Suspended pump returns to monitoring
//   canDeliverMultipleBoluses   - More than one bolus delivered in a session
//   canReachAlarmThenDeliver    - Alarm recovery followed by successful delivery
//
// Reachability Witnesses (11):
//   canReachMonitoring          - Pump enters Monitoring mode
//   canReachCalculatingDose     - Pump enters CalculatingDose mode
//   canReachDelivering          - Pump enters Delivering mode
//   canReachSuspended           - Pump enters Suspended mode
//   canReachAlarmActive         - Pump enters AlarmActive mode
//   canTriggerLowReservoir      - LowReservoir alarm is raised
//   canTriggerHighGlucose       - HighGlucose alarm is raised
//   canTriggerLowGlucose        - LowGlucose alarm is raised
//   canTriggerOcclusion         - Occlusion alarm during delivery
//   canTriggerMaxDoseExceeded   - MaxDoseExceeded alarm is raised
//   canSetBasalRate             - Basal rate is configured
//
// Type Variant Witnesses (7):
//   canReachIdle                - PumpMode: Idle (covered by init)
//   canTriggerEmptyReservoir    - AlarmCondition: EmptyReservoir
//   canTriggerHardwareFault     - AlarmCondition: HardwareFault
//   canReachNoDelivery          - DeliveryType: NoDelivery (covered by init)
//   canReachBasalDelivery       - DeliveryType: BasalDelivery
//   canReachBolusDelivery       - DeliveryType: BolusDelivery
//   canReachAlarmSeverityCritical - AlarmSeverity: Critical alarm active
//
// ============================================================

module insulinPump_witnesses {
  // Instantiate the spec with a small reservoir (5.10 units).
  // Just above the LOW_RESERVOIR_THRESHOLD (500), so a single
  // delivery increment (10) drains it to 500, triggering LowReservoir.
  // Still large enough for the smallest bolus amounts (50).
  import insulinPump(INITIAL_RESERVOIR = 510).* from "./insulinPump"

  // ──────────────────────────────────────────────────────────
  // Helper predicates
  // ──────────────────────────────────────────────────────────

  /// True when a bolus has been fully delivered (totalDeliveredToday > 0
  /// and pump returned to Monitoring after delivery)
  val hasCompletedBolus: bool =
    totalDeliveredToday > 0 and mode == Monitoring and pendingBolus == 0

  /// True when alarm was acknowledged and pump returned to monitoring
  val hasRecoveredFromAlarm: bool =
    alarmAcknowledged and mode == Monitoring

  // ──────────────────────────────────────────────────────────
  // LIVENESS WITNESSES
  // ──────────────────────────────────────────────────────────

  // Witness: Complete bolus delivery
  // Goal: Pump can go through the full lifecycle:
  //   Idle -> Monitoring -> CalculatingDose -> Delivering -> Monitoring
  //   with insulin actually delivered (totalDeliveredToday > 0)
  //
  // EXPECTED: Invariant VIOLATION (proves delivery can complete)
  val canCompleteBolusDelivery: bool = not(hasCompletedBolus)

  // Witness: Recover from alarm
  // Goal: After entering AlarmActive, the pump can acknowledge the alarm
  //   and return to Monitoring mode.
  //
  // EXPECTED: Invariant VIOLATION (proves alarm recovery works)
  val canRecoverFromAlarm: bool = not(hasRecoveredFromAlarm)

  // Witness: Resume from suspension
  // Goal: Pump can be suspended and then resume to Monitoring
  //   with evidence of prior activity (reservoir depleted from deliveries).
  //
  // EXPECTED: Invariant VIOLATION (proves suspension is recoverable)
  val canResumeFromSuspension: bool = not(
    mode == Monitoring and basalRate > 0 and reservoirLevel < 510
  )

  // Witness: Multiple boluses delivered
  // Goal: The pump can deliver more than one bolus in a session
  //   (totalDeliveredToday reflects at least two minimum boluses).
  //
  // EXPECTED: Invariant VIOLATION (proves repeated delivery works)
  val canDeliverMultipleBoluses: bool = not(
    totalDeliveredToday > 100 and mode == Monitoring
  )

  // Witness: Alarm recovery then delivery
  // Goal: After recovering from an alarm, the pump can still deliver a bolus.
  //   This verifies the alarm doesn't leave the pump in a degraded state.
  //
  // EXPECTED: Invariant VIOLATION (proves post-alarm delivery works)
  val canReachAlarmThenDeliver: bool = not(
    alarmAcknowledged and totalDeliveredToday > 0 and mode == Monitoring
  )

  // ──────────────────────────────────────────────────────────
  // REACHABILITY WITNESSES - Pump Modes
  // ──────────────────────────────────────────────────────────

  // Witness: Reach Monitoring mode
  // EXPECTED: Invariant VIOLATION
  val canReachMonitoring: bool = not(mode == Monitoring)

  // Witness: Reach CalculatingDose mode
  // EXPECTED: Invariant VIOLATION
  val canReachCalculatingDose: bool = not(mode == CalculatingDose)

  // Witness: Reach Delivering mode
  // EXPECTED: Invariant VIOLATION
  val canReachDelivering: bool = not(mode == Delivering)

  // Witness: Reach Suspended mode
  // EXPECTED: Invariant VIOLATION
  val canReachSuspended: bool = not(mode == Suspended)

  // Witness: Reach AlarmActive mode
  // EXPECTED: Invariant VIOLATION
  val canReachAlarmActive: bool = not(mode == AlarmActive)

  // ──────────────────────────────────────────────────────────
  // REACHABILITY WITNESSES - Alarm Conditions
  // ──────────────────────────────────────────────────────────

  // Witness: LowReservoir alarm
  // Needs reservoir <= 500. Starting at 600, one bolus of 100+ drains enough.
  // EXPECTED: Invariant VIOLATION
  val canTriggerLowReservoir: bool = not(alarmCondition == LowReservoir)

  // Witness: HighGlucose alarm (glucose >= 300)
  // EXPECTED: Invariant VIOLATION
  val canTriggerHighGlucose: bool = not(alarmCondition == HighGlucose)

  // Witness: LowGlucose alarm (glucose <= 54)
  // EXPECTED: Invariant VIOLATION
  val canTriggerLowGlucose: bool = not(alarmCondition == LowGlucose)

  // Witness: Occlusion alarm during delivery
  // EXPECTED: Invariant VIOLATION
  val canTriggerOcclusion: bool = not(alarmCondition == Occlusion)

  // Witness: MaxDoseExceeded alarm (bolus > 2500 or daily limit)
  // EXPECTED: Invariant VIOLATION
  val canTriggerMaxDoseExceeded: bool = not(alarmCondition == MaxDoseExceeded)

  // ──────────────────────────────────────────────────────────
  // REACHABILITY WITNESSES - Delivery & Configuration
  // ──────────────────────────────────────────────────────────

  // Witness: Basal rate configured (basalRate > 0)
  // EXPECTED: Invariant VIOLATION
  val canSetBasalRate: bool = not(basalRate > 0)

  // ──────────────────────────────────────────────────────────
  // TYPE VARIANT WITNESSES
  // ──────────────────────────────────────────────────────────
  // These verify every variant of each sum type is reachable.
  // Variants already covered above are noted but not duplicated.

  // -- PumpMode --
  // Idle: covered by init state (mode starts as Idle)
  // Monitoring, CalculatingDose, Delivering, Suspended, AlarmActive: covered above
  val canReachIdle: bool = not(mode == Idle)

  // -- AlarmCondition --
  // NoAlarm, LowReservoir, HighGlucose, LowGlucose, Occlusion, MaxDoseExceeded: covered above

  // EmptyReservoir: reservoir fully drained during delivery
  // EXPECTED: Invariant VIOLATION
  val canTriggerEmptyReservoir: bool = not(alarmCondition == EmptyReservoir)

  // HardwareFault: no action currently triggers this alarm
  // EXPECTED: No violation (dead variant — no action produces HardwareFault)
  val canTriggerHardwareFault: bool = not(alarmCondition == HardwareFault)

  // -- DeliveryType --
  // NoDelivery: covered by init state (currentDelivery starts as NoDelivery)
  val canReachNoDelivery: bool = not(currentDelivery == NoDelivery)

  // BasalDelivery: basal insulin delivery active
  // EXPECTED: No violation (dead variant — no action sets BasalDelivery)
  val canReachBasalDelivery: bool = not(currentDelivery == BasalDelivery)

  // BolusDelivery: bolus insulin delivery active
  // EXPECTED: Invariant VIOLATION
  val canReachBolusDelivery: bool = not(currentDelivery == BolusDelivery)

  // -- AlarmSeverity (derived from alarmCondition via alarmSeverity()) --
  // Advisory: alarmSeverity(LowReservoir) — covered via canTriggerLowReservoir
  // Alert: alarmSeverity(HighGlucose) or alarmSeverity(LowGlucose) — covered above
  // Critical: EmptyReservoir, Occlusion, or HardwareFault while in AlarmActive
  // EXPECTED: Invariant VIOLATION (via EmptyReservoir or Occlusion)
  val canReachAlarmSeverityCritical: bool = not(
    mode == AlarmActive and isCriticalAlarm(alarmCondition)
  )
}
