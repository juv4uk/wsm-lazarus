/* Близнюк C для навантаження `fib`.
   Те саме тіло, що й у нативному ELF SENS: рекурсивне fib на стеку.
   Протокол: програма завершується кодом fib(N) & 255, N вшитий у код —
   так само, як у нашому ELF, де N приходить із точного D24 `.sens`. */
#include <stdlib.h>

static unsigned long fib(unsigned long n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    return (int)(fib(N) & 255UL);
}
