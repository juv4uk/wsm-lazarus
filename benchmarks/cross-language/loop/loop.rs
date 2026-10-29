// G6.141 — близнюк навантаження `loop` мовою Rust.
// Те саме тіло: N разів додати K, код виходу = сума & 255.
use std::env;

fn main() {
    let n: u64 = env::var("LOOP_N").ok().and_then(|s| s.parse().ok()).unwrap_or(1_000_000);
    let k: u64 = env::var("LOOP_K").ok().and_then(|s| s.parse().ok()).unwrap_or(1);
    let mut acc: u64 = 0;
    let mut i: u64 = 0;
    while i < n {
        acc = acc.wrapping_add(k);
        i += 1;
    }
    std::process::exit((acc & 255) as i32);
}
