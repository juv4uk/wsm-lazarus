// Близнюк Rust для навантаження `fib`.
// Те саме тіло: рекурсивне fib на стеку.
// Протокол: exit(fib(N) & 255), N вшитий у код.
use std::process::exit;

// N вшитий у код через згенерований include — так само, як у C (-D).
include!("fib_n.rs");

#[inline(never)]
fn fib(n: u64) -> u64 {
    if n < 2 {
        return n;
    }
    fib(n - 1) + fib(n - 2)
}

fn main() {
    exit((fib(N) & 255) as i32);
}
