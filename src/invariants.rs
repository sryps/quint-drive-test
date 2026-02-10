// Safety invariants — direct translation from the Quint spec's `val` invariants.

use crate::constants::*;
use crate::logic::is_critical_alarm;
use crate::types::*;

/// Quint: val reservoirNonNegative = reservoirLevel >= 0
pub fn reservoir_non_negative(state: &State) -> bool {
    state.reservoir_level >= 0
}

/// Quint: val bolusWithinLimit = pendingBolus <= MAX_SINGLE_BOLUS
pub fn bolus_within_limit(state: &State) -> bool {
    state.pending_bolus <= MAX_SINGLE_BOLUS
}

/// Quint: val dailyDoseWithinLimit = totalDeliveredToday <= MAX_DAILY_DOSE
pub fn daily_dose_within_limit(state: &State) -> bool {
    state.total_delivered_today <= MAX_DAILY_DOSE
}

/// Quint: val deliveryOnlyWhenDelivering =
///   (currentDelivery != NoDelivery) implies (mode == Delivering)
pub fn delivery_only_when_delivering(state: &State) -> bool {
    if state.current_delivery != DeliveryType::NoDelivery {
        state.mode == PumpMode::Delivering
    } else {
        true
    }
}

/// Quint: val criticalAlarmStopsDelivery =
///   isCriticalAlarm(alarmCondition) implies (currentDelivery == NoDelivery)
pub fn critical_alarm_stops_delivery(state: &State) -> bool {
    if is_critical_alarm(state.alarm_condition) {
        state.current_delivery == DeliveryType::NoDelivery
    } else {
        true
    }
}

/// Quint: val noDeliveryWhenEmpty =
///   (reservoirLevel <= 0) implies (currentDelivery == NoDelivery)
pub fn no_delivery_when_empty(state: &State) -> bool {
    if state.reservoir_level <= 0 {
        state.current_delivery == DeliveryType::NoDelivery
    } else {
        true
    }
}

/// All individual invariants with names for reporting.
pub const ALL_INVARIANTS: &[(&str, fn(&State) -> bool)] = &[
    ("reservoirNonNegative", reservoir_non_negative),
    ("bolusWithinLimit", bolus_within_limit),
    ("dailyDoseWithinLimit", daily_dose_within_limit),
    ("deliveryOnlyWhenDelivering", delivery_only_when_delivering),
    ("criticalAlarmStopsDelivery", critical_alarm_stops_delivery),
    ("noDeliveryWhenEmpty", no_delivery_when_empty),
];

/// Quint: val safetyInvariant = and { ... }
pub fn safety_invariant(state: &State) -> bool {
    ALL_INVARIANTS.iter().all(|(_, check)| check(state))
}

/// Check all invariants and return the name of the first violated one, if any.
pub fn check_invariants(state: &State) -> Result<(), &'static str> {
    for (name, check) in ALL_INVARIANTS {
        if !check(state) {
            return Err(name);
        }
    }
    Ok(())
}
