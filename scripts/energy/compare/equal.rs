use std::hint::black_box;
use std::io::{self, BufRead, Write};

#[inline(never)]
fn exact_equal(left: u64, right: u64) -> bool {
    left == right
}

fn main() -> io::Result<()> {
    let stdin = io::stdin();
    let mut stdout = io::BufWriter::new(io::stdout().lock());
    writeln!(stdout, "READY")?;
    stdout.flush()?;
    for line in stdin.lock().lines() {
        let count: u64 = line?.parse().map_err(|_| io::ErrorKind::InvalidInput)?;
        if count == 0 || count > 1_000_000_000 {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "count out of range"));
        }
        let equal_fn = black_box(exact_equal as fn(u64, u64) -> bool);
        let mut matches = 0u64;
        for i in 0..count {
            let value = black_box((i * 17 + 3) & 255);
            matches += u64::from(equal_fn(value, value));
        }
        if matches != count {
            return Err(io::Error::other("incorrect equality result"));
        }
        writeln!(stdout, "OK\t{count}\t{}", matches * 161)?;
        stdout.flush()?;
    }
    Ok(())
}

// Питання: яку роль тут має black_box? Чому функція не вбудовується?
// Який результат перевіряє matches? Чому протокол не вимірює cold start?
