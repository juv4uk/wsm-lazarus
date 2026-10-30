//! Вимірювальний адаптер до production `sens_dot_scalar` та `sens_dot_avx2`.
//!
//! Це не реалізація закону SENS і не копія ядра: функції приходять з
//! `machine_math_skylake.S` за C ABI. Два `Vec<f64>` мають довжину `n`,
//! зберігаються до завершення всіх викликів і передаються як pointer+length.
//! Вихід — один сумарний f64, не точне число D12+ чи SENS-значення.
//!
//! Запит: kernel, n, repetitions. Обидва kernel отримують ті самі дані й
//! кількість викликів; окремий процес дозволяє виміряти один шлях за раз.
//!
//! Питання для перевірки розуміння:
//! 1. Чому `Vec` живий до останнього виклику assembly?
//! 2. Які гарантії довжини й ABI потрібні для безпечного `unsafe` виклику?
//! 3. Чому RAPL package delta не є джоулями саме цього процесу?

use std::env;
use std::process::ExitCode;

unsafe extern "C" {
    fn sens_dot_scalar(a: *const f64, b: *const f64, n: usize) -> f64;
    fn sens_dot_avx2(a: *const f64, b: *const f64, n: usize) -> f64;
}

type Kernel = unsafe extern "C" fn(*const f64, *const f64, usize) -> f64;

fn run(args: &[String]) -> Result<f64, String> {
    if args.len() != 3 {
        return Err("використання: worker <sse2|avx2> <n> <repetitions>".into());
    }
    let n: usize = args[1].parse().map_err(|_| "некоректне n")?;
    let repetitions: usize = args[2].parse().map_err(|_| "некоректна кількість повторів")?;
    if n == 0 || repetitions == 0 || n > 16_777_216 || repetitions > 1_000_000 {
        return Err("n і кількість повторів мають бути додатними та обмеженими".into());
    }
    let kernel: Kernel = match args[0].as_str() {
        "sse2" => sens_dot_scalar,
        "avx2" => sens_dot_avx2,
        _ => return Err("ядро має бути sse2 або avx2".into()),
    };
    let a: Vec<f64> = (0..n).map(|i| (i % 251) as f64 * 0.5).collect();
    let b: Vec<f64> = (0..n).map(|i| (i % 253) as f64 * 0.25).collect();
    // Match dot_bench's one-call warmup; it is included in the RAPL interval.
    let _warmup = unsafe { kernel(a.as_ptr(), b.as_ptr(), n) };
    let mut total = 0.0_f64;
    for _ in 0..repetitions {
        // SAFETY: vectors remain live; both have length n; selected kernel
        // is from the exact x86-64 System V source selected by the caller.
        total += unsafe { kernel(a.as_ptr(), b.as_ptr(), n) };
    }
    Ok(total)
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    match run(&args) {
        Ok(value) if value.is_finite() => {
            println!("{value:.16e}");
            ExitCode::SUCCESS
        }
        Ok(_) => {
            eprintln!("ядро повернуло нескінченний результат");
            ExitCode::from(4)
        }
        Err(message) => {
            eprintln!("{message}");
            ExitCode::from(64)
        }
    }
}
