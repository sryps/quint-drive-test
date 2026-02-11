// Model-Based Testing — deterministic trace replay.
// Given a sequence of TransitionLabels, applies each to the Rust logic
// and returns the resulting state sequence for comparison against the Quint spec.

use crate::invariants;
use crate::logic;
use crate::types::*;

/// Apply a single labeled transition to the state.
/// Dispatches to the correct logic function using parameters embedded in the label.
pub fn apply_transition(state: &State, label: &TransitionLabel) -> TransitionResult {
    match label {
        TransitionLabel::NoAction => TransitionResult {
            success: true,
            new_state: state.clone(),
        },
        TransitionLabel::StartMonitoring => logic::start_monitoring(state),
        TransitionLabel::ProcessGlucose { reading } => {
            logic::process_glucose_reading(state, *reading)
        }
        TransitionLabel::RequestBolus { amount } => logic::request_bolus(state, *amount),
        TransitionLabel::ConfirmDelivery => logic::confirm_delivery(state),
        TransitionLabel::DeliverIncrement => logic::deliver_increment(state, 10),
        TransitionLabel::HandleOcclusion => logic::handle_occlusion(state),
        TransitionLabel::CancelDelivery => logic::cancel_delivery(state),
        TransitionLabel::AcknowledgeAlarm => logic::acknowledge_alarm(state),
        TransitionLabel::SuspendPump => logic::suspend_pump(state),
        TransitionLabel::ResumePump => logic::resume_pump(state),
        TransitionLabel::StartBasal { rate } => logic::start_basal(state, *rate),
        TransitionLabel::DeliverBasal => logic::deliver_basal(state),
        TransitionLabel::DetectHardwareFault => logic::detect_hardware_fault(state),
    }
}

/// Replay a full trace of labeled transitions starting from `init`.
/// Each step must succeed; panics with a descriptive message if a transition fails.
/// Returns the sequence of (label, resulting state) pairs.
pub fn replay_trace(
    init: State,
    labels: &[TransitionLabel],
) -> Vec<(TransitionLabel, State)> {
    let mut trace = Vec::with_capacity(labels.len());
    let mut state = init;

    for (i, label) in labels.iter().enumerate() {
        let result = apply_transition(&state, label);
        assert!(
            result.success,
            "Transition {} ({}) failed at step {} from state:\n{}",
            label,
            std::any::type_name::<TransitionLabel>(),
            i,
            state,
        );

        // Check invariants hold after each step
        if let Err(violated) = invariants::check_invariants(&result.new_state) {
            panic!(
                "Invariant '{}' violated after step {} ({})\nState:\n{}",
                violated, i, label, result.new_state,
            );
        }

        state = result.new_state;
        trace.push((label.clone(), state.clone()));
    }

    trace
}
