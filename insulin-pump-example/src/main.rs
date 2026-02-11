use std::env;

use insulin_pump_sim::invariants;
use insulin_pump_sim::simulator;

fn main() {
    let args: Vec<String> = env::args().collect();

    let max_steps: usize = parse_flag(&args, "--max-steps").unwrap_or(20);
    let max_samples: usize = parse_flag(&args, "--max-samples").unwrap_or(10000);
    let seed: u64 = parse_flag(&args, "--seed").unwrap_or_else(|| {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos() as u64
    });
    let verbose = args.iter().any(|a| a == "--verbose" || a == "-v");

    println!("Insulin Pump Simulator");
    println!("======================");
    println!("Based on Quint spec: specs/insulinPump.qnt");
    println!();
    println!(
        "Running {} traces of {} steps each (seed: {})",
        max_samples, max_steps, seed
    );
    if verbose {
        println!("Verbose mode: showing first trace\n");
    }

    println!("Checking invariants:");
    for (name, _) in invariants::ALL_INVARIANTS {
        println!("  - {}", name);
    }

    let result = simulator::run_simulation(max_steps, max_samples, seed, verbose);
    println!("{}", result);
}

fn parse_flag<T: std::str::FromStr>(args: &[String], flag: &str) -> Option<T> {
    for i in 0..args.len() {
        if args[i].starts_with(&format!("{}=", flag)) {
            return args[i].split('=').nth(1).and_then(|v| v.parse().ok());
        }
        if args[i] == flag {
            return args.get(i + 1).and_then(|v| v.parse().ok());
        }
    }
    None
}
