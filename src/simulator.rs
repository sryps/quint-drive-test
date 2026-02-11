// Simulator — mirrors the Quint spec's nondeterministic `step` action.
// Uses random selection to model the `nondet ... oneOf()` and `any { ... }` constructs.

use rand::seq::SliceRandom;
use rand::Rng;

use crate::constants::*;
use crate::invariants;
use crate::logic;
use crate::types::*;

/// The set of actions the simulator can choose from, matching the Quint `step` action.
#[derive(Debug, Clone, Copy)]
pub enum Action {
    StartMonitoring,
    ProcessGlucose,
    RequestBolus,
    ConfirmDelivery,
    DeliverIncrement,
    HandleOcclusion,
    CancelDelivery,
    AcknowledgeAlarm,
    SuspendPump,
    ResumePump,
    StartBasal,
    DeliverBasal,
    DetectHardwareFault,
}

const ALL_ACTIONS: &[Action] = &[
    Action::StartMonitoring,
    Action::ProcessGlucose,
    Action::RequestBolus,
    Action::ConfirmDelivery,
    Action::DeliverIncrement,
    Action::HandleOcclusion,
    Action::CancelDelivery,
    Action::AcknowledgeAlarm,
    Action::SuspendPump,
    Action::ResumePump,
    Action::StartBasal,
    Action::DeliverBasal,
    Action::DetectHardwareFault,
];

/// Quint: action init
pub fn init_state() -> State {
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

/// Result of executing an action with its resolved label (including params).
struct LabeledResult {
    result: TransitionResult,
    label: TransitionLabel,
}

/// Execute a single nondeterministic step, mirroring the Quint `step` action.
/// Returns the transition label (with resolved params) and the new state.
pub fn step(state: &State, rng: &mut impl Rng) -> (TransitionLabel, State) {
    // Quint's `any { ... }` picks one enabled action nondeterministically.
    // We shuffle the action list and try each until one succeeds (changes state),
    // falling back to unchanged state if none are enabled.
    let mut actions: Vec<Action> = ALL_ACTIONS.to_vec();
    actions.shuffle(rng);

    for action in &actions {
        let labeled = execute_action_labeled(state, *action, rng);
        if labeled.result.success {
            return (labeled.label, labeled.result.new_state);
        }
    }

    // No action was enabled — state is unchanged (matches Quint's unchanged_all fallback)
    (TransitionLabel::NoAction, state.clone())
}

/// Execute a specific action with nondeterministic parameters, returning the resolved label.
fn execute_action_labeled(state: &State, action: Action, rng: &mut impl Rng) -> LabeledResult {
    match action {
        Action::StartMonitoring => LabeledResult {
            result: logic::start_monitoring(state),
            label: TransitionLabel::StartMonitoring,
        },
        Action::ProcessGlucose => {
            let reading = *GLUCOSE_LEVELS.choose(rng).unwrap();
            LabeledResult {
                result: logic::process_glucose_reading(state, reading),
                label: TransitionLabel::ProcessGlucose { reading },
            }
        }
        Action::RequestBolus => {
            let amount = *BOLUS_AMOUNTS.choose(rng).unwrap();
            LabeledResult {
                result: logic::request_bolus(state, amount),
                label: TransitionLabel::RequestBolus { amount },
            }
        }
        Action::ConfirmDelivery => LabeledResult {
            result: logic::confirm_delivery(state),
            label: TransitionLabel::ConfirmDelivery,
        },
        Action::DeliverIncrement => LabeledResult {
            result: logic::deliver_increment(state, 10),
            label: TransitionLabel::DeliverIncrement,
        },
        Action::HandleOcclusion => LabeledResult {
            result: logic::handle_occlusion(state),
            label: TransitionLabel::HandleOcclusion,
        },
        Action::CancelDelivery => LabeledResult {
            result: logic::cancel_delivery(state),
            label: TransitionLabel::CancelDelivery,
        },
        Action::AcknowledgeAlarm => LabeledResult {
            result: logic::acknowledge_alarm(state),
            label: TransitionLabel::AcknowledgeAlarm,
        },
        Action::SuspendPump => LabeledResult {
            result: logic::suspend_pump(state),
            label: TransitionLabel::SuspendPump,
        },
        Action::ResumePump => LabeledResult {
            result: logic::resume_pump(state),
            label: TransitionLabel::ResumePump,
        },
        Action::StartBasal => {
            let rate = *BASAL_RATES.choose(rng).unwrap();
            LabeledResult {
                result: logic::start_basal(state, rate),
                label: TransitionLabel::StartBasal { rate },
            }
        }
        Action::DeliverBasal => LabeledResult {
            result: logic::deliver_basal(state),
            label: TransitionLabel::DeliverBasal,
        },
        Action::DetectHardwareFault => LabeledResult {
            result: logic::detect_hardware_fault(state),
            label: TransitionLabel::DetectHardwareFault,
        },
    }
}

/// Result of running one simulation trace.
pub struct TraceResult {
    pub steps: usize,
    pub violation: Option<(&'static str, usize, State)>,
    pub final_state: State,
}

/// Run a single simulation trace for up to `max_steps`.
/// Checks all safety invariants after each step.
pub fn run_trace(max_steps: usize, rng: &mut impl Rng, verbose: bool) -> TraceResult {
    let mut state = init_state();

    if verbose {
        println!("[State 0] init");
        println!("{}\n", state);
    }

    // Check invariants on initial state
    if let Err(violated) = invariants::check_invariants(&state) {
        return TraceResult {
            steps: 0,
            violation: Some((violated, 0, state.clone())),
            final_state: state,
        };
    }

    for step_num in 1..=max_steps {
        let (label, new_state) = step(&state, rng);

        if verbose {
            let changed = new_state != state;
            if changed {
                println!("[State {}] {}", step_num, label);
                println!("{}\n", new_state);
            }
        }

        state = new_state;

        if let Err(violated) = invariants::check_invariants(&state) {
            if verbose {
                println!(
                    "!!! INVARIANT VIOLATION: {} at step {}",
                    violated, step_num
                );
            }
            return TraceResult {
                steps: step_num,
                violation: Some((violated, step_num, state.clone())),
                final_state: state,
            };
        }
    }

    TraceResult {
        steps: max_steps,
        violation: None,
        final_state: state,
    }
}

/// Run many simulation traces, matching Quint's `--max-samples` behavior.
pub fn run_simulation(
    max_steps: usize,
    max_samples: usize,
    seed: u64,
    verbose: bool,
) -> SimulationResult {
    use rand::SeedableRng;
    let mut rng = rand::rngs::StdRng::seed_from_u64(seed);

    let start = std::time::Instant::now();
    let mut violation = None;

    for trace_num in 0..max_samples {
        let result = run_trace(max_steps, &mut rng, verbose && trace_num == 0);

        if let Some((inv_name, step, state)) = result.violation {
            violation = Some(ViolationInfo {
                invariant: inv_name,
                trace: trace_num,
                step,
                state,
            });
            break;
        }
    }

    let elapsed = start.elapsed();

    SimulationResult {
        max_steps,
        max_samples,
        seed,
        elapsed,
        violation,
    }
}

pub struct ViolationInfo {
    pub invariant: &'static str,
    pub trace: usize,
    pub step: usize,
    pub state: State,
}

pub struct SimulationResult {
    pub max_steps: usize,
    pub max_samples: usize,
    pub seed: u64,
    pub elapsed: std::time::Duration,
    pub violation: Option<ViolationInfo>,
}

impl std::fmt::Display for SimulationResult {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let traces_per_sec = self.max_samples as f64 / self.elapsed.as_secs_f64();
        writeln!(f)?;
        match &self.violation {
            None => {
                writeln!(
                    f,
                    "[ok] No violation found ({:.0}ms at {:.0} traces/second).",
                    self.elapsed.as_millis(),
                    traces_per_sec,
                )?;
                writeln!(
                    f,
                    "Checked {} traces of {} steps each.",
                    self.max_samples, self.max_steps,
                )?;
            }
            Some(v) => {
                writeln!(
                    f,
                    "[VIOLATION] Invariant '{}' violated at trace {} step {}.",
                    v.invariant, v.trace, v.step,
                )?;
                writeln!(f, "State at violation:")?;
                writeln!(f, "{}", v.state)?;
            }
        }
        writeln!(f, "Seed: {} ", self.seed)
    }
}
