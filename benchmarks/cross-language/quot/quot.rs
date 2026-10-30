// G6.176: Rust twin for one exact D5 quotient using the packed T5M host ABI.
// The Vec is owned by this process and holds at most the six-byte input frame;
// output is a stack [u8; 3]. There is no SENS-law registry in this transport.
// Questions: Why read the complete frame? Why preserve its T5M byte form?
// Why reject overflow instead of truncating? What does this benchmark include?
use std::io::{self, Read, Write};
use std::process;

fn fail() -> ! {
    let _ = io::stderr().write_all(b"D12 quotient frame rejected\n");
    process::exit(2)
}

fn signed(trits: &[u8]) -> i32 {
    if trits.len() != 12 || trits.iter().any(|digit| *digit > 1) {
        fail();
    }
    let mut value = 0u32;
    for digit in trits {
        value = (value << 1) | u32::from(*digit);
    }
    if trits[0] == 1 { value as i32 - 4096 } else { value as i32 }
}

fn pack_result(value: i32) -> [u8; 3] {
    if !(-2048..=2047).contains(&value) { fail(); }
    let bits = (value as u32) & 0x0fff;
    let mut output = [0u8; 3];
    for (group, byte) in output.iter_mut().enumerate() {
        let mut packed = 0u32;
        for offset in 0..5 {
            let index = group * 5 + offset;
            let digit = if index < 12 { (bits >> (11 - index)) & 1 } else { 2 };
            packed = packed * 3 + digit;
        }
        if packed >= 243 { fail(); }
        *byte = packed as u8;
    }
    output
}

fn main() {
    let mut frame = Vec::with_capacity(7);
    if io::stdin().read_to_end(&mut frame).is_err() || frame.len() != 6 {
        fail();
    }
    let mut trits = [0u8; 30];
    for (index, byte) in frame.iter().copied().enumerate() {
        if byte >= 243 { fail(); }
        let mut value = u32::from(byte);
        for digit in (0..5).rev() {
            trits[index * 5 + digit] = (value % 3) as u8;
            value /= 3;
        }
        if value != 0 { fail(); }
    }
    if trits[12..15].iter().any(|digit| *digit != 2) ||
        trits[27..].iter().any(|digit| *digit != 2) {
        fail();
    }
    let left = signed(&trits[..12]);
    let right = signed(&trits[15..27]);
    if right == 0 || left % right != 0 { fail(); }
    let quotient = left / right;
    let output = pack_result(quotient);
    if io::stdout().write_all(&output).is_err() { fail(); }
}
