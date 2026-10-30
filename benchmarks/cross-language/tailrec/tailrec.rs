// G6.156 — близнюк хвостової рекурсії мовою Rust.
use std::env;
fn count_down(n: u64, acc: u64) -> u64 {
    if n < 1 { return acc; }
    count_down(n - 1, acc + 1)   // хвіст
}
fn main() {
    let n: u64 = env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    std::process::exit((count_down(n, 0) & 255) as i32);
}
