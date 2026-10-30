/* G6.176: C twin for one exact D5 quotient, with the same packed T5M ABI. */
/*
 * Input is borrowed stdin bytes (6-byte pair frame); output is three owned
 * stack bytes written before process exit. No heap allocation or partial
 * stdout occurs before the whole frame and quotient are validated.
 * Questions: Why are the two padding regions distinct? Why use signed D12?
 * Why does a non-zero remainder fail? Why is RAPL package energy not PID energy?
 */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>

static int fail(void) {
    static const char message[] = "D12 quotient frame rejected\n";
    const ssize_t written = write(STDERR_FILENO, message, sizeof(message) - 1);
    if (written < 0) return 2;
    return 2;
}

static int unpack(const uint8_t *frame, uint8_t *trits) {
    for (size_t i = 0; i < 6; ++i) {
        unsigned value = frame[i];
        if (value >= 243) return 0;
        for (int j = 4; j >= 0; --j) {
            trits[i * 5 + (size_t)j] = (uint8_t)(value % 3);
            value /= 3;
        }
        if (value != 0) return 0;
    }
    return 1;
}

static int decode_signed(const uint8_t *trits, int32_t *out) {
    uint32_t value = 0;
    for (size_t i = 0; i < 12; ++i) {
        if (trits[i] > 1) return 0;
        value = (value << 1) | trits[i];
    }
    *out = (trits[0] != 0) ? (int32_t)value - 4096 : (int32_t)value;
    return 1;
}

static int encode_result(int32_t value, uint8_t *out) {
    if (value < -2048 || value > 2047) return 0;
    uint32_t bits = (uint32_t)value & 0xFFFu;
    for (size_t group = 0; group < 3; ++group) {
        unsigned packed = 0;
        for (size_t offset = 0; offset < 5; ++offset) {
            const size_t index = group * 5 + offset;
            unsigned digit = index < 12
                ? (bits >> (11u - (unsigned)index)) & 1u : 2u;
            packed = packed * 3u + digit;
        }
        if (packed >= 243) return 0;
        out[group] = (uint8_t)packed;
    }
    return 1;
}

int main(void) {
    uint8_t frame[7] = {0}, trits[30] = {0}, result[3] = {0};
    const ssize_t count = read(STDIN_FILENO, frame, sizeof(frame));
    if (count != 6 || !unpack(frame, trits)) return fail();
    for (size_t i = 12; i < 15; ++i) if (trits[i] != 2) return fail();
    for (size_t i = 27; i < 30; ++i) if (trits[i] != 2) return fail();
    int32_t left = 0, right = 0;
    if (!decode_signed(trits, &left) || !decode_signed(trits + 15, &right) ||
        right == 0 || left % right != 0) return fail();
    const int32_t quotient = left / right;
    if (!encode_result(quotient, result)) return fail();
    return write(STDOUT_FILENO, result, sizeof(result)) == 3 ? 0 : fail();
}
