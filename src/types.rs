// Types — direct 1:1 mapping from the Quint spec's sum types and State record.

/// Pump operating mode
/// Quint: type PumpMode = Idle | Monitoring | CalculatingDose | Delivering | Suspended | AlarmActive
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PumpMode {
    Idle,
    Monitoring,
    CalculatingDose,
    Delivering,
    Suspended,
    AlarmActive,
}

/// Alarm severity levels
/// Quint: type AlarmSeverity = Advisory | Alert | Critical
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AlarmSeverity {
    Advisory,
    Alert,
    Critical,
}

/// Specific alarm conditions
/// Quint: type AlarmCondition = NoAlarm | LowReservoir | EmptyReservoir | ...
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AlarmCondition {
    NoAlarm,
    LowReservoir,
    EmptyReservoir,
    Occlusion,
    HighGlucose,
    LowGlucose,
    HardwareFault,
    MaxDoseExceeded,
}

/// Type of insulin delivery
/// Quint: type DeliveryType = NoDelivery | BasalDelivery | BolusDelivery
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeliveryType {
    NoDelivery,
    BasalDelivery,
    BolusDelivery,
}

/// Quint: type GlucoseLevel = int
pub type GlucoseLevel = i64;

/// Quint: type InsulinUnits = int (scaled by 100, e.g. 150 = 1.50 units)
pub type InsulinUnits = i64;

/// Full pump state
/// Quint: type State = { mode, glucoseLevel, reservoirLevel, ... }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct State {
    pub mode: PumpMode,
    pub glucose_level: GlucoseLevel,
    pub reservoir_level: InsulinUnits,
    pub current_delivery: DeliveryType,
    pub delivered_amount: InsulinUnits,
    pub pending_bolus: InsulinUnits,
    pub basal_rate: InsulinUnits,
    pub alarm_condition: AlarmCondition,
    pub alarm_acknowledged: bool,
    pub total_delivered_today: InsulinUnits,
}

/// Labels for each transition, enabling deterministic trace replay.
/// Quint: type ActionLabel
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransitionLabel {
    NoAction,
    StartMonitoring,
    ProcessGlucose { reading: GlucoseLevel },
    RequestBolus { amount: InsulinUnits },
    ConfirmDelivery,
    DeliverIncrement,
    HandleOcclusion,
    CancelDelivery,
    AcknowledgeAlarm,
    SuspendPump,
    ResumePump,
    StartBasal { rate: InsulinUnits },
    DeliverBasal,
    DetectHardwareFault,
}

impl std::fmt::Display for TransitionLabel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TransitionLabel::NoAction => write!(f, "NoAction"),
            TransitionLabel::StartMonitoring => write!(f, "StartMonitoring"),
            TransitionLabel::ProcessGlucose { reading } => {
                write!(f, "ProcessGlucose({})", reading)
            }
            TransitionLabel::RequestBolus { amount } => {
                write!(f, "RequestBolus({})", amount)
            }
            TransitionLabel::ConfirmDelivery => write!(f, "ConfirmDelivery"),
            TransitionLabel::DeliverIncrement => write!(f, "DeliverIncrement"),
            TransitionLabel::HandleOcclusion => write!(f, "HandleOcclusion"),
            TransitionLabel::CancelDelivery => write!(f, "CancelDelivery"),
            TransitionLabel::AcknowledgeAlarm => write!(f, "AcknowledgeAlarm"),
            TransitionLabel::SuspendPump => write!(f, "SuspendPump"),
            TransitionLabel::ResumePump => write!(f, "ResumePump"),
            TransitionLabel::StartBasal { rate } => write!(f, "StartBasal({})", rate),
            TransitionLabel::DeliverBasal => write!(f, "DeliverBasal"),
            TransitionLabel::DetectHardwareFault => write!(f, "DetectHardwareFault"),
        }
    }
}

/// Result of a pure transition function.
/// Quint: { success: bool, newState: State }
pub struct TransitionResult {
    pub success: bool,
    pub new_state: State,
}

/// Result of a bolus safety check.
/// Quint: { allowed: bool, reason: AlarmCondition }
pub struct BolusCheck {
    pub allowed: bool,
    pub reason: AlarmCondition,
}

impl std::fmt::Display for PumpMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl std::fmt::Display for AlarmCondition {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl std::fmt::Display for DeliveryType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl std::fmt::Display for State {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "  mode:                 {}", self.mode)?;
        writeln!(f, "  glucose_level:        {} mg/dL", self.glucose_level)?;
        writeln!(
            f,
            "  reservoir_level:      {:.2} units",
            self.reservoir_level as f64 / 100.0
        )?;
        writeln!(f, "  current_delivery:     {}", self.current_delivery)?;
        writeln!(
            f,
            "  delivered_amount:     {:.2} units",
            self.delivered_amount as f64 / 100.0
        )?;
        writeln!(
            f,
            "  pending_bolus:        {:.2} units",
            self.pending_bolus as f64 / 100.0
        )?;
        writeln!(
            f,
            "  basal_rate:           {:.2} units/step",
            self.basal_rate as f64 / 100.0
        )?;
        writeln!(f, "  alarm_condition:      {}", self.alarm_condition)?;
        writeln!(f, "  alarm_acknowledged:   {}", self.alarm_acknowledged)?;
        write!(
            f,
            "  total_delivered_today: {:.2} units",
            self.total_delivered_today as f64 / 100.0
        )
    }
}
