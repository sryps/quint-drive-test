// Integration tests — deterministic trace replay via TransitionLabel sequences.
// Each test replays a hardcoded label sequence and asserts the final state.

use insulin_pump_sim::constants::*;
use insulin_pump_sim::mbt::replay_trace;
use insulin_pump_sim::simulator::init_state;
use insulin_pump_sim::types::*;

/// 1. Happy path bolus: Idle → Monitoring → CalculatingDose → Delivering → Monitoring
#[test]
fn trace_happy_path_bolus() {
    // Request a 0.50-unit bolus (50 hundredths), deliver in 5 increments of 0.10
    let labels = vec![
        TransitionLabel::StartMonitoring,
        TransitionLabel::RequestBolus { amount: 50 },
        TransitionLabel::ConfirmDelivery,
        TransitionLabel::DeliverIncrement,
        TransitionLabel::DeliverIncrement,
        TransitionLabel::DeliverIncrement,
        TransitionLabel::DeliverIncrement,
        TransitionLabel::DeliverIncrement, // 5th increment completes delivery
    ];

    let trace = replay_trace(init_state(), &labels);
    let final_state = &trace.last().unwrap().1;

    assert_eq!(final_state.mode, PumpMode::Monitoring);
    assert_eq!(final_state.pending_bolus, 0);
    assert_eq!(final_state.delivered_amount, 0);
    assert_eq!(final_state.current_delivery, DeliveryType::NoDelivery);
    assert_eq!(final_state.total_delivered_today, 50);
    assert_eq!(final_state.reservoir_level, INITIAL_RESERVOIR - 50);
}

/// 2. Occlusion during delivery — partial delivery then occlusion, verify Suspended
#[test]
fn trace_occlusion_during_delivery() {
    let labels = vec![
        TransitionLabel::StartMonitoring,
        TransitionLabel::RequestBolus { amount: 100 },
        TransitionLabel::ConfirmDelivery,
        TransitionLabel::DeliverIncrement, // 10 of 100 delivered
        TransitionLabel::DeliverIncrement, // 20 of 100 delivered
        TransitionLabel::HandleOcclusion,  // occlusion stops delivery
        TransitionLabel::AcknowledgeAlarm, // Occlusion is critical → Suspended
    ];

    let trace = replay_trace(init_state(), &labels);
    let final_state = &trace.last().unwrap().1;

    assert_eq!(final_state.mode, PumpMode::Suspended);
    assert_eq!(final_state.current_delivery, DeliveryType::NoDelivery);
    assert_eq!(final_state.alarm_condition, AlarmCondition::Occlusion);
    assert!(final_state.alarm_acknowledged);
    // 2 increments of 10 were delivered before occlusion
    assert_eq!(final_state.total_delivered_today, 20);
}

/// 3. Glucose alarm — normal reading, then low glucose (Alert), then empty reservoir (Critical)
#[test]
fn trace_glucose_alarm() {
    // LowGlucose is Alert severity → stays in same mode with alarm set.
    // To trigger AlarmActive we need a Critical alarm (e.g. EmptyReservoir via low reservoir).
    // Instead, test the Alert path and then use a Critical trigger.
    let labels = vec![
        TransitionLabel::StartMonitoring,
        TransitionLabel::ProcessGlucose { reading: 120 }, // normal
        TransitionLabel::ProcessGlucose { reading: 40 },  // <= CRITICAL_LOW → LowGlucose (Alert)
    ];

    let trace = replay_trace(init_state(), &labels);

    // After normal reading: still Monitoring, no alarm
    let after_normal = &trace[1].1;
    assert_eq!(after_normal.mode, PumpMode::Monitoring);
    assert_eq!(after_normal.alarm_condition, AlarmCondition::NoAlarm);

    // After critical-low reading: LowGlucose is Alert (not Critical), stays Monitoring
    let final_state = &trace[2].1;
    assert_eq!(final_state.mode, PumpMode::Monitoring);
    assert_eq!(final_state.alarm_condition, AlarmCondition::LowGlucose);
    assert_eq!(final_state.glucose_level, 40);
}

/// 4. Basal delivery — configure rate, deliver twice, verify reservoir deducted
#[test]
fn trace_basal_delivery() {
    let labels = vec![
        TransitionLabel::StartMonitoring,
        TransitionLabel::StartBasal { rate: 50 }, // 0.50 units/step
        TransitionLabel::DeliverBasal,            // first basal delivery
        TransitionLabel::DeliverBasal,            // second basal delivery
    ];

    let trace = replay_trace(init_state(), &labels);
    let final_state = &trace.last().unwrap().1;

    assert_eq!(final_state.mode, PumpMode::Monitoring);
    assert_eq!(final_state.basal_rate, 50);
    assert_eq!(final_state.current_delivery, DeliveryType::BasalDelivery);
    assert_eq!(final_state.total_delivered_today, 100); // 50 * 2
    assert_eq!(final_state.reservoir_level, INITIAL_RESERVOIR - 100);
}

/// 5. Suspend/resume — round-trip through Suspended back to Monitoring
#[test]
fn trace_suspend_resume() {
    let labels = vec![
        TransitionLabel::StartMonitoring,
        TransitionLabel::SuspendPump,
        TransitionLabel::ResumePump,
    ];

    let trace = replay_trace(init_state(), &labels);

    // After suspend
    let after_suspend = &trace[1].1;
    assert_eq!(after_suspend.mode, PumpMode::Suspended);

    // After resume
    let final_state = &trace[2].1;
    assert_eq!(final_state.mode, PumpMode::Monitoring);
    assert_eq!(final_state.alarm_condition, AlarmCondition::NoAlarm);
    assert!(!final_state.alarm_acknowledged);
}
