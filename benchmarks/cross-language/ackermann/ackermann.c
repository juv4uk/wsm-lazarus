/* G6.145 — близнюк навантаження `ackermann` мовою C.
   Те саме тіло, що й нативне SENS-зниження (wsm.lowerd24):
   ack(m,n) = n+1 | ack(m-1,1) | ack(m-1, ack(m,n-1)).
   Код виходу = результат & 255. */
#include <stdio.h>
#include <stdlib.h>

static unsigned long long ack(unsigned long long m, unsigned long long n)
{
    if (m == 0) return n + 1;
    if (n == 0) return ack(m - 1, 1);
    return ack(m - 1, ack(m, n - 1));
}

int main(int argc, char **argv)
{
    unsigned long long m = (argc > 1) ? strtoull(argv[1], NULL, 10) : 2;
    unsigned long long n = (argc > 2) ? strtoull(argv[2], NULL, 10) : 2;
    return (int)(ack(m, n) & 255ULL);
}
