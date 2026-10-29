// G6.150 — близнюк навантаження `evenodd` мовою Rust.
use std::env;

fn even(n: u64) -> u64 {
    if n < 1 { return 1; }
    odd(n - 1)
}
fn odd(n: u64) -> u64 {
    if n < 1 { return 0; }
    even(n - 1)
}

fn main() {
    let n: u64 = env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    std::process::exit((even(n) & 255) as i32);
}
