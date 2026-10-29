use std::env;

fn main() {
    let count: u64 = env::args().nth(1).unwrap().parse().unwrap();
    let mut sum: u32 = 0;
    for i in (1..=count).rev() {
        sum = sum.wrapping_add(i as u32);
    }
    std::process::exit((sum & 255) as i32);
}
