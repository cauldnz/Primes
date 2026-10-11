// Prime sieve drag race - C++ solution by cauldnz.
// Base algorithm, faithful, 1 bit per odd number.
//
// The base algorithm: an outer loop finds the next prime, then clears every one of its odd
// multiples individually. Bit i of the sieve stands for the odd number 2i + 1; a set bit means
// composite. In this source every composite is cleared by its own single-bit OR: no operation
// sets more than one composite.
//
// Two clearing routines, after the approach of mike-barber's Rust and GordonBGood's Chapel
// solutions:
//
//  * Dense (factor < DenseLimit): the odd multiples of p repeat with a period of p 64-bit
//    words, holding exactly 64 multiples at fixed (word, bit) positions. The routine is a
//    template instantiated for every odd factor below the limit, so those positions and masks
//    are compile-time constants. The compiler merges the ORs that land in one word into one
//    constant and vectorises the period's words. Every odd factor gets an instance, not only
//    primes: the program uses no knowledge of which numbers are prime beyond 2 being even.
//  * Sparse (larger factors): the same idea over bytes. Eight multiples repeat every p bytes,
//    each with a fixed bit position; their byte offsets are computed per factor, and the eight
//    masks are compile-time constants selected by p mod 16.

#include <sched.h>
#if defined(__x86_64__) || defined(__i386__)
#include <cpuid.h>
#endif
#include <unistd.h>

#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <thread>
#include <utility>
#include <vector>

#define ALWAYS_INLINE [[gnu::always_inline]] inline

namespace {

constexpr int DenseLimit = 128;   // odd factors below this use the dense routine

// Dense clearing for a compile-time odd factor P over one period of P words starting at q.
// Bit P/2 + j*P (j = 0..63) of the period is the odd multiple P*(2j + 1). With Init, the
// period's words are zeroed first instead of read: the factor-3 pass initialises the sieve.
template <int P, bool Init, std::size_t... J>
ALWAYS_INLINE void clear_period(std::uint64_t* __restrict q, std::index_sequence<J...>) {
    if constexpr (Init) {
        for (int k = 0; k < P; k++) q[k] = 0;
    }
    ((q[(P / 2 + J * P) >> 6] |= std::uint64_t{1} << ((P / 2 + J * P) & 63)), ...);
}

template <int P, bool Init, bool Restore = true>
ALWAYS_INLINE void clear_dense(std::uint64_t* __restrict w, std::size_t nwords) {
    constexpr std::size_t first = std::size_t((P * P / 2) / 64 / P) * P;   // period holding P*P
    // Clearing starts at the period that holds P*P. Its smaller multiples are composite too;
    // only P itself is restored at the end.
    std::uint64_t* __restrict q = w + first;
    for (std::size_t n = nwords > first ? (nwords - first) / P : 0; n > 0; n--, q += P)
        clear_period<P, Init>(q, std::make_index_sequence<64>{});

    const std::size_t left = nwords > first ? std::size_t(w + nwords - q) : 0;  // last period
    if constexpr (Init) std::memset(q, 0, left * sizeof *q);
    for (int j = 0; j < 64; j++) {
        const int t = P / 2 + j * P;
        if (std::size_t(t >> 6) >= left) break;
        q[t >> 6] |= std::uint64_t{1} << (t & 63);                      // one composite
    }
    constexpr int f = P / 2;                                           // P itself is prime
    if (Restore && std::size_t(f >> 6) < nwords) w[f >> 6] &= ~(std::uint64_t{1} << (f & 63));
}

template <int P>
void dense(std::uint64_t* w, std::size_t nwords) { clear_dense<P, P == 3>(w, nwords); }

#ifdef __AVX512F__
// Wide dense clearing for factors 65..127, where GCC's own vectorisation of clear_period falls
// back to 128-bit and scalar ORs (some words of a period hold no multiple). Eight periods make
// 8P words, which split evenly into P blocks of eight words. Each block gets one 512-bit OR:
// each of its eight lanes builds its own word's mask, one single-bit OR per composite in that
// word. The word offsets are compile-time constants, so the masks fold to constants.
using Vec8 = std::uint64_t __attribute__((vector_size(64), aligned(8)));

template <int P, std::size_t B>
ALWAYS_INLINE void clear_block(std::uint64_t* __restrict q) {
    Vec8 v = {};
    for (int l = 0; l < 8; l++) {
        const int word = int(B) * 8 + l;                                 // in the 8 periods
        for (int t = ((P / 2 - 64 * word) % P + P) % P; t < 64; t += P)  // bits P apart
            v[l] |= std::uint64_t{1} << t;                               // one composite
    }
    *reinterpret_cast<Vec8*>(q + B * 8) |= v;
}

template <int P, std::size_t... B>
ALWAYS_INLINE void clear_octet(std::uint64_t* __restrict q, std::index_sequence<B...>) {
    (clear_block<P, B>(q), ...);
}

template <int P>
void dense_wide(std::uint64_t* w, std::size_t nwords) {
    static_assert(P > 64 && P < 128);   // P*P lies in the first period: clearing starts at w
    std::uint64_t* __restrict q = w;
    for (std::size_t n = nwords / (8 * P); n > 0; n--, q += 8 * P)
        clear_octet<P>(q, std::make_index_sequence<P>{});
    // The remaining periods through the 64-bit routine, then restore P itself.
    clear_dense<P, false, false>(q, nwords - std::size_t(q - w));
    constexpr int f = P / 2;
    if (std::size_t(f >> 6) < nwords) w[f >> 6] &= ~(std::uint64_t{1} << (f & 63));
}
#endif

// One dense routine per odd factor below DenseLimit, indexed by factor / 2. Factor 3 always
// runs first, so its routine also initialises the sieve.
template <std::size_t... I>
constexpr auto dense_table(std::index_sequence<I...>) {
    using Fn = void (*)(std::uint64_t*, std::size_t);
    return std::array<Fn, sizeof...(I)>{(I == 0 ? nullptr : &dense<int(2 * I + 1)>)...};
}
constexpr auto dense_routines = dense_table(std::make_index_sequence<DenseLimit / 2>{});

#ifdef __AVX512F__
template <int P>
constexpr auto pick_wide() {
    if constexpr (P > 64) return &dense_wide<P>;
    else return &dense<P>;
}

template <std::size_t... I>
constexpr auto dense_wide_table(std::index_sequence<I...>) {
    using Fn = void (*)(std::uint64_t*, std::size_t);
    return std::array<Fn, sizeof...(I)>{(I == 0 ? nullptr : pick_wide<int(2 * I + 1)>())...};
}
constexpr auto dense_routines_wide =
    dense_wide_table(std::make_index_sequence<DenseLimit / 2>{});
#endif

// Sparse clearing over bytes for an odd factor p > 16. In each p-byte chunk the eight
// multiples sit at bit offsets p/2 + j*p (j = 0..7). Their bit-in-byte positions depend only
// on E = p mod 16, so the masks are constants.
template <int E>
void clear_sparse(std::uint8_t* __restrict bytes, std::size_t nbytes, std::size_t p) {
    std::size_t o[8];
    for (int j = 0; j < 8; j++) o[j] = (p / 2 + j * p) >> 3;
    constexpr auto bit = [](int j) { return std::uint8_t(1u << ((E / 2 + j * E) & 7)); };

    // A pointer walks over the chunks, so each OR is one instruction with a register offset.
    const std::size_t first = ((p * p / 2) / 8 / p) * p;
    std::uint8_t* __restrict q = bytes + first;
    for (std::size_t n = (nbytes - first) / p; n > 0; n--, q += p) {   // one composite each
        q[o[0]] |= bit(0); q[o[1]] |= bit(1); q[o[2]] |= bit(2); q[o[3]] |= bit(3);
        q[o[4]] |= bit(4); q[o[5]] |= bit(5); q[o[6]] |= bit(6); q[o[7]] |= bit(7);
    }
    const std::size_t left = std::size_t(bytes + nbytes - q);
    for (int j = 0; j < 8 && o[j] < left; j++)                         // partial last chunk
        q[o[j]] |= std::uint8_t(1u << ((E / 2 + j * E) & 7));
}

// The sieve class: the whole state of one sieve. A new instance is made for every pass.
class Sieve {
public:
    // wide: use the 512-bit dense routines, for runs where each sieve thread has a core.
    explicit Sieve(std::uint64_t size, bool wide = false)
        : size_(size), nbits_((size + 1) / 2), nwords_((nbits_ + 63) / 64), wide_(wide) {
        const std::size_t bytes = (nwords_ * 8 + 63) / 64 * 64;
        void* p = nullptr;
        if (posix_memalign(&p, 64, bytes) != 0) throw std::bad_alloc();
        bits_ = static_cast<std::uint64_t*>(p);
        // Only word 0 is cleared, so the scan can read the bit for 3. The first factor is
        // always 3, and its dense pass writes every word, which initialises the rest.
        bits_[0] = 0;
    }
    ~Sieve() { std::free(bits_); }
    Sieve(const Sieve&) = delete;
    Sieve& operator=(const Sieve&) = delete;

    // The base algorithm: find the next prime, clear its multiples, repeat up to sqrt(size).
    void run() {
        std::uint64_t q = std::uint64_t(std::sqrt(double(size_)));
        while ((q + 1) * (q + 1) <= size_) q++;
        while (q * q > size_) q--;
        for (std::uint64_t factor = 3; factor <= q; factor += 2) {
            std::uint64_t i = factor / 2;
            while (i < nbits_ && is_composite(i)) i++;                 // next prime
            factor = 2 * i + 1;
            if (factor > q) break;
            clear_factor(factor);
        }
    }

    // Primes up to and including size: clear bits for 3..size, plus the prime 2.
    std::uint64_t count() const {
        if (size_ < 2) return 0;
        std::uint64_t c = 1;
        for (std::uint64_t i = 1; i < nbits_; i++) c += !is_composite(i);
        return c;
    }

private:
    bool is_composite(std::uint64_t i) const { return (bits_[i / 64] >> (i % 64)) & 1; }

    void clear_factor(std::uint64_t p) {
        if (p < DenseLimit) {
#ifdef __AVX512F__
            if (wide_) { dense_routines_wide[p / 2](bits_, nwords_); return; }
#endif
            dense_routines[p / 2](bits_, nwords_);
            return;
        }
        auto* b = reinterpret_cast<std::uint8_t*>(bits_);
        const std::size_t n = nwords_ * 8;
        switch (p & 15) {
            case 1:  clear_sparse<1>(b, n, p);  break;
            case 3:  clear_sparse<3>(b, n, p);  break;
            case 5:  clear_sparse<5>(b, n, p);  break;
            case 7:  clear_sparse<7>(b, n, p);  break;
            case 9:  clear_sparse<9>(b, n, p);  break;
            case 11: clear_sparse<11>(b, n, p); break;
            case 13: clear_sparse<13>(b, n, p); break;
            default: clear_sparse<15>(b, n, p); break;
        }
    }

    std::uint64_t size_;
    std::uint64_t nbits_;
    std::size_t nwords_;
    bool wide_;
    std::uint64_t* bits_;
};

// ---------------------------------------------------------------------------------------
// Benchmark driver
// ---------------------------------------------------------------------------------------
constexpr std::uint64_t SieveSize = 1'000'000;
constexpr std::uint64_t Expected = 78'498;
constexpr auto RunTime = std::chrono::seconds(5);
using Clock = std::chrono::steady_clock;

struct Result {
    std::uint64_t passes = 0;
    std::uint64_t count = 0;   // prime count from the first pass, for validation
};

Result worker(Clock::time_point deadline, bool wide) {
    Result r;
    while (Clock::now() < deadline) {
        Sieve s(SieveSize, wide);
        s.run();
        if (r.passes == 0) r.count = s.count();
        r.passes++;
    }
    return r;
}

void report(std::uint64_t passes, Clock::duration elapsed, unsigned threads) {
    std::printf("cauldnz-cpp-base;%llu;%f;%u;algorithm=base,faithful=yes,bits=1\n",
                static_cast<unsigned long long>(passes),
                std::chrono::duration<double>(elapsed).count(), threads);
    std::fflush(stdout);
}

[[noreturn]] void fail_count() {
    std::fputs("ERROR: wrong prime count\n", stderr);
    std::exit(1);
}

// wide: each thread has a core to itself (no SMT sibling sieving next to it).
void run_threads(unsigned n, bool wide) {
    const auto start = Clock::now();
    const auto deadline = start + RunTime;
    std::vector<Result> results(n);
    std::vector<std::thread> threads;
    threads.reserve(n);
    for (unsigned t = 0; t < n; t++)
        threads.emplace_back([&results, t, deadline, wide] {
            results[t] = worker(deadline, wide);
        });
    std::uint64_t total = 0;
    for (unsigned t = 0; t < n; t++) {
        threads[t].join();
        total += results[t].passes;
        if (results[t].count != Expected) fail_count();
    }
    report(total, Clock::now() - start, n);
}

// CPUs this process may run on: a container's --cpuset-cpus limit shows up here.
unsigned available_cpus() {
    cpu_set_t set;
    if (sched_getaffinity(0, sizeof set, &set) == 0) {
        const int n = CPU_COUNT(&set);
        if (n > 0) return unsigned(n);
    }
    const unsigned n = std::thread::hardware_concurrency();
    return n > 0 ? n : 1;
}

// PRIMES_TEST=1: prime counts at every power of ten to 10^8 and a few awkward sizes.
// PRIMES_TEST=2: the count for every size to 5,000, then every 997th to 400,000.
[[noreturn]] void self_test(int mode) {
    if (mode == 2) {
        for (std::uint64_t n = 1; n < 400'000; n = (n < 5'000) ? n + 1 : n + 997) {
            Sieve s(n), sw(n, true);
            s.run();
            sw.run();
            std::printf("%llu %llu\n", static_cast<unsigned long long>(n),
                        static_cast<unsigned long long>(s.count()));
            if (sw.count() != s.count()) {
                std::fprintf(stderr, "wide mismatch at %llu\n", static_cast<unsigned long long>(n));
                std::exit(1);
            }
        }
        std::exit(0);
    }
    constexpr std::pair<std::uint64_t, std::uint64_t> cases[] = {
        {1, 0}, {2, 1}, {3, 2}, {10, 4}, {100, 25}, {1'000, 168}, {10'000, 1'229},
        {100'000, 9'592}, {1'000'000, 78'498}, {10'000'000, 664'579},
        {100'000'000, 5'761'455}, {127, 31}, {16'383, 1'900}};
    int bad = 0;
    for (bool wide : {false, true}) {
        for (auto [size, expect] : cases) {
            Sieve s(size, wide);
            s.run();
            const std::uint64_t c = s.count();
            std::printf("%s size %llu -> %llu primes (expected %llu) %d\n",
                        wide ? "wide" : "narrow", static_cast<unsigned long long>(size),
                        static_cast<unsigned long long>(c),
                        static_cast<unsigned long long>(expect), c == expect ? 1 : 0);
            if (c != expect) bad = 1;
        }
    }
    std::exit(bad);
}

// Zen 5 (AMD family 1Ah). The 512-bit dense routines gain about 6% at one thread there; the
// ISPC base's same idea lost 3% on Zen 4 and 7% on Intel Ice Lake, so they run on Zen 5 only.
bool is_zen5() {
#if defined(__x86_64__) || defined(__i386__)
    unsigned a, b, c, d;
    if (!__get_cpuid(0, &a, &b, &c, &d)) return false;
    const bool amd = b == 0x68747541 && d == 0x69746e65 && c == 0x444d4163;  // "AuthenticAMD"
    if (!__get_cpuid(1, &a, &b, &c, &d)) return false;
    unsigned family = (a >> 8) & 0xF;
    if (family == 0xF) family += (a >> 20) & 0xFF;
    return amd && family == 0x1A;
#else
    return false;
#endif
}

}  // namespace

int main() {
    if (const char* t = std::getenv("PRIMES_TEST"); t != nullptr && std::atoi(t) != 0)
        self_test(std::atoi(t));

    const bool zen5 = is_zen5();
    const auto start = Clock::now();
    const Result r = worker(start + RunTime, zen5);
    const auto elapsed = Clock::now() - start;
    if (r.count != Expected) fail_count();
    report(r.passes, elapsed, 1);

    // One independent sieve per thread at all, half and a quarter of the available CPUs:
    // where SMT siblings share an L1, fewer threads can complete more passes.
    const unsigned cpus = available_cpus();
    for (unsigned n = cpus; n >= 2 && n * 4 >= cpus; n /= 2) run_threads(n, zen5 && 2 * n <= cpus);
    return 0;
}
