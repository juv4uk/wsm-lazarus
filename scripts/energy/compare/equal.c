#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

__attribute__((noinline)) static int exact_equal(uint64_t left, uint64_t right) {
    return left == right;
}

int main(void) {
    uint64_t count;
    char line[64];
    int (*volatile equal_fn)(uint64_t, uint64_t) = exact_equal;
    puts("READY");
    fflush(stdout);
    while (fgets(line, sizeof line, stdin)) {
        char *end = NULL;
        count = strtoull(line, &end, 10);
        if (end == line || count == 0 || count > UINT64_C(1000000000)) return 2;
        uint64_t matches = 0;
        for (uint64_t i = 0; i < count; ++i) {
            uint64_t value = (i * UINT64_C(17) + UINT64_C(3)) & UINT64_C(255);
            matches += (uint64_t)equal_fn(value, value);
        }
        if (matches != count) return 3;
        printf("OK\t%" PRIu64 "\t%" PRIu64 "\n", count, matches * UINT64_C(161));
        fflush(stdout);
    }
    return 0;
}

/* Питання: що гарантує noinline? Навіщо вказівник volatile? Які межі count?
   Чому checksum дорівнює кількості збігів, помноженій на 161? */
