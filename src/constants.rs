// Constants — mirrors the Quint spec's `pure val` declarations exactly.

use crate::types::{GlucoseLevel, InsulinUnits};

// Glucose thresholds (mg/dL)
pub const GLUCOSE_LOW: GlucoseLevel = 70;
pub const GLUCOSE_HIGH: GlucoseLevel = 180;
pub const GLUCOSE_CRITICAL_LOW: GlucoseLevel = 54;
pub const GLUCOSE_CRITICAL_HIGH: GlucoseLevel = 300;
pub const GLUCOSE_TARGET: GlucoseLevel = 120;

// Insulin limits (in hundredths of units)
pub const MAX_SINGLE_BOLUS: InsulinUnits = 2500; // 25.00 units
pub const MAX_DAILY_DOSE: InsulinUnits = 10000; // 100.00 units
pub const LOW_RESERVOIR_THRESHOLD: InsulinUnits = 500; // 5.00 units remaining
pub const INITIAL_RESERVOIR: InsulinUnits = 20000; // 200.00 units (full cartridge)

// Nondeterministic selection sets from the spec
pub const BASAL_RATES: &[InsulinUnits] = &[10, 25, 50, 75, 100];
pub const BOLUS_AMOUNTS: &[InsulinUnits] = &[50, 100, 200, 500, 1000, 2000, 2500, 3000];
pub const GLUCOSE_LEVELS: &[GlucoseLevel] = &[40, 54, 70, 100, 120, 150, 180, 250, 300, 350];
