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

/// Execute a single nondeterministic step, mirroring the Quint `step` action.
/// Returns the action taken and whether the state actually changed.
pub fn step(state: &State, rng: &mut impl Rng) -> (Action, State) {
    // Quint's `any { ... }` picks one enabled action nondeterministically.
    // We shuffle the action list and try each until one succeeds (changes state),
    // falling back to unchanged state if none are enabled.
    let mut actions: Vec<Action> = ALL_ACTIONS.to_vec();
    actions.shuffle(rng);

    for action in &actions {
        let result = execute_action(state, *action, rng);
        if result.success {
            return (*action, result.new_state);
        }
    }

    // No action was enabled — state is unchanged (matches Quint's unchanged_all fallback)
    (actions[0], state.clone())
}

/// Execute a specific action with nondeterministic parameters.
fn execute_action(state: &State, action: Action, rng: &mut impl Rng) -> TransitionResult {
    match action {
        Action::StartMonitoring => logic::start_monitoring(state),
        Action::ProcessGlucose => {
            let reading = *GLUCOSE_LEVELS.choose(rng).unwrap();
            logic::process_glucose_reading(state, reading)
        }
        Action::RequestBolus => {
            let amount = *BOLUS_AMOUNTS.choose(rng).unwrap();
            logic::request_bolus(state, amount)
        }
        Action::ConfirmDelivery => logic::confirm_delivery(state),
        Action::DeliverIncrement => logic::deliver_increment(state, 10),
        Action::HandleOcclusion => logic::handle_occlusion(state),
        Action::CancelDelivery => logic::cancel_delivery(state),
        Action::AcknowledgeAlarm => logic::acknowledge_alarm(state),
        Action::SuspendPump => logic::suspend_pump(state),
        Action::ResumePump => logic::resume_pump(state),
        Action::StartBasal => {
            let rate = *BASAL_RATES.choose(rng).unwrap();
            logic::start_basal(state, rate)
        }
        Action::DeliverBasal => logic::deliver_basal(state),
        Action::DetectHardwareFault => logic::detect_hardware_fault(state),
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
        let (action, new_state) = step(&state, rng);

        if verbose {
            let changed = new_state != state;
            if changed {
                println!("[State {}] {:?}", step_num, action);
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
