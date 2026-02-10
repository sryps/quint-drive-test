// Pure functions — all business logic, direct translation from the Quint spec.
// Every function here corresponds to a `pure def` in the spec.

use crate::constants::*;
use crate::types::*;

/// Quint: pure def alarmSeverity(condition)
pub fn alarm_severity(condition: AlarmCondition) -> AlarmSeverity {
    match condition {
        AlarmCondition::NoAlarm => AlarmSeverity::Advisory,
        AlarmCondition::LowReservoir => AlarmSeverity::Advisory,
        AlarmCondition::HighGlucose => AlarmSeverity::Alert,
        AlarmCondition::LowGlucose => AlarmSeverity::Alert,
        AlarmCondition::EmptyReservoir => AlarmSeverity::Critical,
        AlarmCondition::Occlusion => AlarmSeverity::Critical,
        AlarmCondition::HardwareFault => AlarmSeverity::Critical,
        AlarmCondition::MaxDoseExceeded => AlarmSeverity::Critical,
    }
}

/// Quint: pure def isCriticalAlarm(condition)
pub fn is_critical_alarm(condition: AlarmCondition) -> bool {
    alarm_severity(condition) == AlarmSeverity::Critical
}

/// Quint: pure def detectAlarm(state)
pub fn detect_alarm(state: &State) -> AlarmCondition {
    if state.reservoir_level <= 0 {
        AlarmCondition::EmptyReservoir
    } else if state.glucose_level <= GLUCOSE_CRITICAL_LOW {
        AlarmCondition::LowGlucose
    } else if state.glucose_level >= GLUCOSE_CRITICAL_HIGH {
        AlarmCondition::HighGlucose
    } else if state.reservoir_level <= LOW_RESERVOIR_THRESHOLD {
        AlarmCondition::LowReservoir
    } else {
        AlarmCondition::NoAlarm
    }
}

/// Quint: pure def calculateCorrectionBolus(glucose)
pub fn calculate_correction_bolus(glucose: GlucoseLevel) -> InsulinUnits {
    if glucose <= GLUCOSE_TARGET {
        0
    } else {
        let excess = glucose - GLUCOSE_TARGET;
        (excess * 100) / 50
    }
}

/// Quint: pure def isBolusAllowed(state, bolusAmount)
pub fn is_bolus_allowed(state: &State, bolus_amount: InsulinUnits) -> BolusCheck {
    if bolus_amount > MAX_SINGLE_BOLUS {
        BolusCheck {
            allowed: false,
            reason: AlarmCondition::MaxDoseExceeded,
        }
    } else if bolus_amount > state.reservoir_level {
        BolusCheck {
            allowed: false,
            reason: AlarmCondition::EmptyReservoir,
        }
    } else if state.total_delivered_today + bolus_amount > MAX_DAILY_DOSE {
        BolusCheck {
            allowed: false,
            reason: AlarmCondition::MaxDoseExceeded,
        }
    } else {
        BolusCheck {
            allowed: true,
            reason: AlarmCondition::NoAlarm,
        }
    }
}

/// Quint: pure def startMonitoring(state)
pub fn start_monitoring(state: &State) -> TransitionResult {
    if state.mode != PumpMode::Idle {
        TransitionResult {
            success: false,
            new_state: state.clone(),
        }
    } else {
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::Monitoring,
                ..state.clone()
            },
        }
    }
}

/// Quint: pure def processGlucoseReading(state, reading)
pub fn process_glucose_reading(state: &State, reading: GlucoseLevel) -> TransitionResult {
    if state.mode != PumpMode::Monitoring && state.mode != PumpMode::Delivering {
        return TransitionResult {
            success: false,
            new_state: state.clone(),
        };
    }

    let updated = State {
        glucose_level: reading,
        ..state.clone()
    };
    let alarm = detect_alarm(&updated);

    if alarm != AlarmCondition::NoAlarm && is_critical_alarm(alarm) {
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::AlarmActive,
                alarm_condition: alarm,
                alarm_acknowledged: false,
                current_delivery: DeliveryType::NoDelivery,
                pending_bolus: 0,
                ..updated
            },
        }
    } else if alarm != AlarmCondition::NoAlarm {
        TransitionResult {
            success: true,
            new_state: State {
                alarm_condition: alarm,
                ..updated
            },
        }
    } else {
        TransitionResult {
            success: true,
            new_state: State {
                alarm_condition: AlarmCondition::NoAlarm,
                ..updated
            },
        }
    }
}

/// Quint: pure def requestBolus(state, amount)
pub fn request_bolus(state: &State, amount: InsulinUnits) -> TransitionResult {
    if state.mode != PumpMode::Monitoring {
        return TransitionResult {
            success: false,
            new_state: state.clone(),
        };
    }

    let check = is_bolus_allowed(state, amount);
    if !check.allowed {
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::AlarmActive,
                alarm_condition: check.reason,
                alarm_acknowledged: false,
                ..state.clone()
            },
        }
    } else {
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::CalculatingDose,
                pending_bolus: amount,
                ..state.clone()
            },
        }
    }
}

/// Quint: pure def confirmDelivery(state)
pub fn confirm_delivery(state: &State) -> TransitionResult {
    if state.mode != PumpMode::CalculatingDose || state.pending_bolus <= 0 {
        TransitionResult {
            success: false,
            new_state: state.clone(),
        }
    } else {
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::Delivering,
                current_delivery: DeliveryType::BolusDelivery,
                delivered_amount: 0,
                ..state.clone()
            },
        }
    }
}

/// Quint: pure def deliverIncrement(state, amount)
pub fn deliver_increment(state: &State, amount: InsulinUnits) -> TransitionResult {
    if state.mode != PumpMode::Delivering {
        return TransitionResult {
            success: false,
            new_state: state.clone(),
        };
    }

    if state.reservoir_level < amount {
        return TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::AlarmActive,
                alarm_condition: AlarmCondition::EmptyReservoir,
                alarm_acknowledged: false,
                current_delivery: DeliveryType::NoDelivery,
                ..state.clone()
            },
        };
    }

    let new_delivered = state.delivered_amount + amount;
    let remaining = state.pending_bolus - new_delivered;

    if remaining <= 0 {
        // Delivery complete
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::Monitoring,
                current_delivery: DeliveryType::NoDelivery,
                delivered_amount: 0,
                pending_bolus: 0,
                reservoir_level: state.reservoir_level - amount,
                total_delivered_today: state.total_delivered_today + amount,
                ..state.clone()
            },
        }
    } else {
        // Partial delivery, continue
        TransitionResult {
            success: true,
            new_state: State {
                delivered_amount: new_delivered,
                reservoir_level: state.reservoir_level - amount,
                total_delivered_today: state.total_delivered_today + amount,
                ..state.clone()
            },
        }
    }
}

/// Quint: pure def handleOcclusion(state)
pub fn handle_occlusion(state: &State) -> TransitionResult {
    if state.mode != PumpMode::Delivering {
        TransitionResult {
            success: false,
            new_state: state.clone(),
        }
    } else {
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::AlarmActive,
                alarm_condition: AlarmCondition::Occlusion,
                alarm_acknowledged: false,
                current_delivery: DeliveryType::NoDelivery,
                ..state.clone()
            },
        }
    }
}

/// Quint: pure def cancelDelivery(state)
pub fn cancel_delivery(state: &State) -> TransitionResult {
    if state.mode != PumpMode::Delivering && state.mode != PumpMode::CalculatingDose {
        TransitionResult {
            success: false,
            new_state: state.clone(),
        }
    } else {
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::Monitoring,
                current_delivery: DeliveryType::NoDelivery,
                pending_bolus: 0,
                delivered_amount: 0,
                ..state.clone()
            },
        }
    }
}

/// Quint: pure def acknowledgeAlarm(state)
pub fn acknowledge_alarm(state: &State) -> TransitionResult {
    if state.mode != PumpMode::AlarmActive {
        return TransitionResult {
            success: false,
            new_state: state.clone(),
        };
    }

    let can_resume = match state.alarm_condition {
        AlarmCondition::EmptyReservoir => false,
        AlarmCondition::HardwareFault => false,
        AlarmCondition::Occlusion => false,
        _ => true,
    };

    if can_resume {
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::Monitoring,
                alarm_condition: AlarmCondition::NoAlarm,
                alarm_acknowledged: true,
                ..state.clone()
            },
        }
    } else {
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::Suspended,
                alarm_acknowledged: true,
                ..state.clone()
            },
        }
    }
}

/// Quint: pure def suspendPump(state)
pub fn suspend_pump(state: &State) -> TransitionResult {
    if state.mode == PumpMode::Suspended || state.mode == PumpMode::Idle {
        TransitionResult {
            success: false,
            new_state: state.clone(),
        }
    } else {
        TransitionResult {
            success: true,
            new_state: State {
                mode: PumpMode::Suspended,
                current_delivery: DeliveryType::NoDelivery,
                pending_bolus: 0,
                delivered_amount: 0,
                ..state.clone()
            },
        }
    }
}

/// Quint: pure def resumePump(state)
pub fn resume_pump(state: &State) -> TransitionResult {
    if state.mode != PumpMode::Suspended {
        return TransitionResult {
            success: false,
            new_state: state.clone(),
        };
    }

    if state.reservoir_level <= 0 {
        return TransitionResult {
            success: false,
            new_state: state.clone(),
        };
    }

    TransitionResult {
        success: true,
        new_state: State {
            mode: PumpMode::Monitoring,
            alarm_condition: AlarmCondition::NoAlarm,
            alarm_acknowledged: false,
            ..state.clone()
        },
    }
}

/// Quint: pure def startBasal(state, rate)
pub fn start_basal(state: &State, rate: InsulinUnits) -> TransitionResult {
    if state.mode != PumpMode::Monitoring {
        TransitionResult {
            success: false,
            new_state: state.clone(),
        }
    } else {
        TransitionResult {
            success: true,
            new_state: State {
                basal_rate: rate,
                ..state.clone()
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_state() -> State {
        State {
            mode: PumpMode::Idle,
            glucose_level: GLUCOSE_TARGET,
            reservoir_level: INITIAL_RESERVOIR,
            current_delivery: DeliveryType::NoDelivery,
            delivered_amount: 0,
            pending_bolus: 0,
            basal_rate: 0,
            alarm_condition: AlarmCondition::NoAlarm,
            alarm_acknowledged: false,
            total_delivered_today: 0,
        }
    }

    #[test]
    fn test_alarm_severity() {
        assert_eq!(alarm_severity(AlarmCondition::NoAlarm), AlarmSeverity::Advisory);
        assert_eq!(alarm_severity(AlarmCondition::LowReservoir), AlarmSeverity::Advisory);
        assert_eq!(alarm_severity(AlarmCondition::HighGlucose), AlarmSeverity::Alert);
        assert_eq!(alarm_severity(AlarmCondition::Occlusion), AlarmSeverity::Critical);
        assert_eq!(alarm_severity(AlarmCondition::HardwareFault), AlarmSeverity::Critical);
    }

    #[test]
    fn test_is_critical_alarm() {
        assert!(!is_critical_alarm(AlarmCondition::NoAlarm));
        assert!(!is_critical_alarm(AlarmCondition::LowReservoir));
        assert!(is_critical_alarm(AlarmCondition::EmptyReservoir));
        assert!(is_critical_alarm(AlarmCondition::Occlusion));
    }

    #[test]
    fn test_detect_alarm() {
        let state = default_state();
        assert_eq!(detect_alarm(&state), AlarmCondition::NoAlarm);

        let low_reservoir = State {
            reservoir_level: 400,
            ..default_state()
        };
        assert_eq!(detect_alarm(&low_reservoir), AlarmCondition::LowReservoir);

        let empty = State {
            reservoir_level: 0,
            ..default_state()
        };
        assert_eq!(detect_alarm(&empty), AlarmCondition::EmptyReservoir);

        let low_glucose = State {
            glucose_level: 50,
            ..default_state()
        };
        assert_eq!(detect_alarm(&low_glucose), AlarmCondition::LowGlucose);

        let high_glucose = State {
            glucose_level: 350,
            ..default_state()
        };
        assert_eq!(detect_alarm(&high_glucose), AlarmCondition::HighGlucose);
    }

    #[test]
    fn test_calculate_correction_bolus() {
        assert_eq!(calculate_correction_bolus(100), 0);
        assert_eq!(calculate_correction_bolus(120), 0);
        // 170 mg/dL: excess=50, (50*100)/50 = 100 hundredths = 1.00 unit
        assert_eq!(calculate_correction_bolus(170), 100);
        // 220 mg/dL: excess=100, (100*100)/50 = 200 hundredths = 2.00 units
        assert_eq!(calculate_correction_bolus(220), 200);
    }

    #[test]
    fn test_is_bolus_allowed() {
        let state = State {
            mode: PumpMode::Monitoring,
            ..default_state()
        };

        let check = is_bolus_allowed(&state, 100);
        assert!(check.allowed);

        let over_max = is_bolus_allowed(&state, 3000);
        assert!(!over_max.allowed);
        assert_eq!(over_max.reason, AlarmCondition::MaxDoseExceeded);

        let nearly_done = State {
            total_delivered_today: 9900,
            ..state.clone()
        };
        let over_daily = is_bolus_allowed(&nearly_done, 200);
        assert!(!over_daily.allowed);
    }

    #[test]
    fn test_start_monitoring() {
        let idle = default_state();
        let result = start_monitoring(&idle);
        assert!(result.success);
        assert_eq!(result.new_state.mode, PumpMode::Monitoring);

        let monitoring = State {
            mode: PumpMode::Monitoring,
            ..default_state()
        };
        let result = start_monitoring(&monitoring);
        assert!(!result.success);
    }

    #[test]
    fn test_bolus_flow() {
        // Idle -> Monitoring
        let state = default_state();
        let r = start_monitoring(&state);
        assert!(r.success);
        let state = r.new_state;

        // Request bolus of 5.00 units
        let r = request_bolus(&state, 500);
        assert!(r.success);
        assert_eq!(r.new_state.mode, PumpMode::CalculatingDose);
        assert_eq!(r.new_state.pending_bolus, 500);
        let state = r.new_state;

        // Confirm delivery
        let r = confirm_delivery(&state);
        assert!(r.success);
        assert_eq!(r.new_state.mode, PumpMode::Delivering);
        assert_eq!(r.new_state.current_delivery, DeliveryType::BolusDelivery);
        let mut state = r.new_state;

        // Deliver in increments of 0.10 units until complete
        // 500 hundredths / 10 per increment = 50 increments
        for i in 0..50 {
            let r = deliver_increment(&state, 10);
            assert!(r.success);
            state = r.new_state;
            if i < 49 {
                assert_eq!(state.mode, PumpMode::Delivering);
            }
        }

        assert_eq!(state.mode, PumpMode::Monitoring);
        assert_eq!(state.pending_bolus, 0);
        assert_eq!(state.total_delivered_today, 500);
        assert_eq!(state.reservoir_level, INITIAL_RESERVOIR - 500);
    }

    #[test]
    fn test_occlusion_during_delivery() {
        let delivering = State {
            mode: PumpMode::Delivering,
            current_delivery: DeliveryType::BolusDelivery,
            pending_bolus: 500,
            ..default_state()
        };
        let r = handle_occlusion(&delivering);
        assert!(r.success);
        assert_eq!(r.new_state.mode, PumpMode::AlarmActive);
        assert_eq!(r.new_state.alarm_condition, AlarmCondition::Occlusion);
        assert_eq!(r.new_state.current_delivery, DeliveryType::NoDelivery);
    }

    #[test]
    fn test_acknowledge_alarm_critical_suspends() {
        let alarm = State {
            mode: PumpMode::AlarmActive,
            alarm_condition: AlarmCondition::Occlusion,
            ..default_state()
        };
        let r = acknowledge_alarm(&alarm);
        assert!(r.success);
        assert_eq!(r.new_state.mode, PumpMode::Suspended);
    }

    #[test]
    fn test_acknowledge_alarm_non_critical_resumes() {
        let alarm = State {
            mode: PumpMode::AlarmActive,
            alarm_condition: AlarmCondition::HighGlucose,
            ..default_state()
        };
        let r = acknowledge_alarm(&alarm);
        assert!(r.success);
        assert_eq!(r.new_state.mode, PumpMode::Monitoring);
        assert_eq!(r.new_state.alarm_condition, AlarmCondition::NoAlarm);
    }

    #[test]
    fn test_suspend_and_resume() {
        let monitoring = State {
            mode: PumpMode::Monitoring,
            ..default_state()
        };
        let r = suspend_pump(&monitoring);
        assert!(r.success);
        assert_eq!(r.new_state.mode, PumpMode::Suspended);

        let r = resume_pump(&r.new_state);
        assert!(r.success);
        assert_eq!(r.new_state.mode, PumpMode::Monitoring);

        // Cannot resume with empty reservoir
        let suspended_empty = State {
            mode: PumpMode::Suspended,
            reservoir_level: 0,
            ..default_state()
        };
        let r = resume_pump(&suspended_empty);
        assert!(!r.success);
    }

    #[test]
    fn test_cancel_delivery() {
        let delivering = State {
            mode: PumpMode::Delivering,
            current_delivery: DeliveryType::BolusDelivery,
            pending_bolus: 500,
            delivered_amount: 100,
            ..default_state()
        };
        let r = cancel_delivery(&delivering);
        assert!(r.success);
        assert_eq!(r.new_state.mode, PumpMode::Monitoring);
        assert_eq!(r.new_state.pending_bolus, 0);
        assert_eq!(r.new_state.delivered_amount, 0);
    }

    #[test]
    fn test_low_glucose_during_monitoring() {
        // LowGlucose is Alert severity (not Critical), so mode stays Monitoring
        let monitoring = State {
            mode: PumpMode::Monitoring,
            ..default_state()
        };
        let r = process_glucose_reading(&monitoring, 40);
        assert!(r.success);
        assert_eq!(r.new_state.mode, PumpMode::Monitoring);
        assert_eq!(r.new_state.alarm_condition, AlarmCondition::LowGlucose);
    }

    #[test]
    fn test_critical_high_glucose_during_monitoring() {
        // HighGlucose at >= 300 is Alert severity — but detect_alarm checks
        // >= GLUCOSE_CRITICAL_HIGH (300), which maps to HighGlucose (Alert).
        // To trigger AlarmActive we need a Critical alarm like EmptyReservoir.
        let monitoring = State {
            mode: PumpMode::Monitoring,
            reservoir_level: 0,
            ..default_state()
        };
        let r = process_glucose_reading(&monitoring, 120);
        assert!(r.success);
        assert_eq!(r.new_state.mode, PumpMode::AlarmActive);
        assert_eq!(r.new_state.alarm_condition, AlarmCondition::EmptyReservoir);
    }

    #[test]
    fn test_start_basal() {
        let monitoring = State {
            mode: PumpMode::Monitoring,
            ..default_state()
        };
        let r = start_basal(&monitoring, 50);
        assert!(r.success);
        assert_eq!(r.new_state.basal_rate, 50);
    }
}
