# Quint-Driven Development: Insulin Pump Example

A demonstration of **Quint-driven development** — writing a formal [Quint](https://github.com/informalsystems/quint) specification first, then deriving a Rust implementation that stays faithful to the spec transition-by-transition.

The domain (an insulin pump state machine) is a realistic example of safety-critical software where formal methods provide real value. This repo is primarily a testbed for the workflow itself: spec first, implement second, verify with model-based testing.

## What is Quint-Driven Development?

1. **Spec first** — Write a Quint specification that models the system's states, transitions, and safety invariants.
2. **Validate the spec** — Use Quint's simulator to check invariants hold across thousands of random traces, and use witness scenarios to confirm all interesting states are reachable.
3. **Derive the implementation** — Translate the spec to Rust (or any language) with a 1:1 mapping: sum types become enums, the state record becomes a struct, pure functions become pure functions.
4. **Model-based testing** — Replay labeled transition traces through both the spec and implementation to verify they agree at every step.

## Repository Structure

```
specs/
  insulinPump.qnt              # Main Quint spec: types, pure logic, actions
  insulinPump_witnesses.qnt    # Witness scenarios (reachability checks)
src/
  types.rs          # Rust enums/structs mirroring Quint types + TransitionLabel
  constants.rs      # Constants matching Quint pure vals
  logic.rs          # Pure functions — direct translation of Quint pure defs
  invariants.rs     # Safety invariants matching Quint invariants
  simulator.rs      # Nondeterministic simulator (mirrors Quint's `any { ... }`)
  mbt.rs            # Deterministic trace replay for model-based testing
  lib.rs            # Library crate (exports all modules)
  main.rs           # CLI entry point
tests/
  mbt_tests.rs      # Integration tests: hardcoded trace replay scenarios
.github/workflows/
  quint.yml         # CI: typecheck, safety invariants, witness reachability
```

## The Spec

The Quint spec models an insulin pump with six operating modes (Idle, Monitoring, CalculatingDose, Delivering, Suspended, AlarmActive) and 13 transitions covering bolus delivery, basal delivery, glucose monitoring, alarm handling, and suspend/resume.

Key safety invariants enforced:
- Reservoir level never goes negative
- Single bolus never exceeds the max allowed
- Daily total delivery stays within limits
- Delivery only occurs in the correct mode
- Critical alarms always halt delivery
- No delivery when reservoir is empty

## Running

### Quint spec

```bash
# Typecheck
quint typecheck specs/insulinPump.qnt

# Simulate with safety invariant checking
quint run specs/insulinPump.qnt \
  --main=insulinPumpDefault \
  --invariant=safetyInvariant \
  --max-steps=50 --max-samples=1000
```

### Rust implementation

```bash
# Run all tests (18 unit + 5 MBT integration)
cargo test

# Run the simulator
cargo run -- --max-steps=50 --max-samples=1000 --verbose
```

## Transition Labels and Model-Based Testing

Every action in both the Quint spec and the Rust implementation carries a `TransitionLabel` / `ActionLabel` that identifies which transition fired and what nondeterministic parameters were chosen (e.g., `ProcessGlucose(120)`, `RequestBolus(500)`).

This enables deterministic trace replay: given a sequence of labels, `mbt::replay_trace()` applies each to the Rust logic and asserts every step succeeds and all invariants hold. The same label sequence can be extracted from a Quint simulation trace, making it possible to verify the two sides agree state-by-state.

## Prerequisites

- [Quint](https://github.com/informalsystems/quint) (`npm install -g @informalsystems/quint`)
- Rust toolchain (`rustup`)
