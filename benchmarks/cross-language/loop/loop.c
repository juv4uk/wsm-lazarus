/* G6.141 — близнюк навантаження `loop` мовою C.
   Те саме тіло, що й нативний SENS-цикл (wsm.elfd12loop):
   N разів додати сталу K, повернути (сума & 255) як код виходу.
   K — стала навантаження, N — аргумент; жодної іншої роботи. */
#include <stdio.h>
#include <stdlib.h>

#ifndef LOOP_N
#define LOOP_N 1000000
#endif
#ifndef LOOP_K
#define LOOP_K 1
#endif

int main(void)
{
    unsigned long long acc = 0;
    for (unsigned long long i = 0; i < (unsigned long long)LOOP_N; ++i) {
        acc += (unsigned long long)LOOP_K;
#if defined(__GNUC__)
        /* G6.241: порожній GCC register barrier не породжує машинних
           інструкцій, але забороняє замінити N додавань на mov/ret.
           Це лише host-механіка бенчмарка, НЕ новий закон SENS.
           Чому правильний exit-код не доводить виконання циклу?
           Чому не створюємо volatile-запис у пам'ять на кожному кроці?
           Як objdump доводить зворотний перехід усередині main? */
        __asm__ __volatile__("" : "+r"(acc));
#else
#error "Потрібен GNU-compatible compiler barrier для вимірюваного циклу"
#endif
    }
    return (int)(acc & 255ULL);
}
