#include <stdint.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) return 64;
    uint64_t count = strtoull(argv[1], NULL, 10);
    uint32_t sum = 0;
    for (uint64_t i = count; i > 0; --i) sum += (uint32_t)i;
    return (int)(sum & 255);
}
