#include <cstdint>
#include <cstdlib>

int main(int argc, char **argv) {
    if (argc != 2) return 64;
    const auto count = std::strtoull(argv[1], nullptr, 10);
    std::uint32_t sum = 0;
    for (std::uint64_t i = count; i > 0; --i) {
        sum += static_cast<std::uint32_t>(i);
    }
    return static_cast<int>(sum & 255U);
}
