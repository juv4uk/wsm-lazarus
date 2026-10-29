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
    for (unsigned long long i = 0; i < (unsigned long long)LOOP_N; ++i)
        acc += (unsigned long long)LOOP_K;
    return (int)(acc & 255ULL);
}
