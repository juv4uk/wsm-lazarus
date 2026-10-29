// G6.145 — близнюк навантаження `ackermann` мовою Rust.
use std::env;

fn ack(m: u64, n: u64) -> u64 {
    if m == 0 { return n + 1; }
    if n == 0 { return ack(m - 1, 1); }
    ack(m - 1, ack(m, n - 1))
}

fn main() {
    let a: Vec<u64> = env::args().skip(1).filter_map(|s| s.parse().ok()).collect();
    let m = *a.first().unwrap_or(&2);
    let n = *a.get(1).unwrap_or(&2);
    std::process::exit((ack(m, n) & 255) as i32);
}
