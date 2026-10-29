/* G6.150 — близнюк навантаження `evenodd` мовою C.
   Взаємна рекурсія: парне/непарне кликають одна одну.
   Код виходу = 1, якщо n парне, інакше 0. */
#include <stdio.h>
#include <stdlib.h>

static unsigned long long odd(unsigned long long n);
static unsigned long long even(unsigned long long n);

static unsigned long long even(unsigned long long n)
{
    if (n < 1) return 1;
    return odd(n - 1);
}
static unsigned long long odd(unsigned long long n)
{
    if (n < 1) return 0;
    return even(n - 1);
}

int main(int argc, char **argv)
{
    unsigned long long n = (argc > 1) ? strtoull(argv[1], NULL, 10) : 0;
    return (int)(even(n) & 255ULL);
}
