/* G6.156 — близнюк хвостової рекурсії мовою C. */
#include <stdlib.h>
static unsigned long long count_down(unsigned long long n, unsigned long long acc)
{
    if (n < 1) return acc;
    return count_down(n - 1, acc + 1);   /* хвіст */
}
int main(int argc, char **argv)
{
    unsigned long long n = (argc > 1) ? strtoull(argv[1], NULL, 10) : 0;
    return (int)(count_down(n, 0) & 255ULL);
}
