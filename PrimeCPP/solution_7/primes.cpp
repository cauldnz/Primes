// Prime sieve drag race - C++ solution by cauldnz.
// Wheel algorithm, faithful, 1 bit per number coprime to 30.
//
// Sieve of Eratosthenes on a mod-30 wheel. Only numbers coprime to 30 are stored, as eight
// bit-planes, one per residue R in {1, 7, 11, 13, 17, 19, 23, 29}; bit m of plane R stands for
// the number 30m + R, and a set bit means composite. Within one plane the multiples of a prime
// p form a plain stride-p progression, so every (prime, plane) pair is an ordinary bit-stride
// sieve whose word pattern repeats every p words. Small primes stream those patterns into the
// planes a block of words at a time; large primes set single bits.

#include <sched.h>
#include <x86intrin.h>

#include <algorithm>
#include <array>
#include <bit>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <new>
#include <thread>
#include <utility>
#include <vector>

namespace {

using Word = std::uint64_t;

// DIAGNOSTIC BUILD (hc/diag-cpp-wheel-phases, never merged): TSC cycles per phase, the same
// split as the ISPC wheel's diagnostic. Each boundary reads the TSC once and charges the time
// since the previous boundary to one slot, so the slots add up to the whole pass.
enum {
    P_SO_DENSE,    // (a) start_bit for group members, all 8 planes
    P_SO_SPARSE,   // (a) start_bit for sparse primes, all 8 planes
    P_SO_TILE,     // (a) start_bit for 7, 11 and 13 per plane
    P_PAT,         // (b) group pattern building (Group::build) for groups of 17+
    P_TILE_BUILD,  // (d) 7x11 pattern build, tile marked in place, 13's pattern build
    P_GROUP,       // (c) fused group passes over the 8 planes (+ member bit clear)
    P_TILE_COPY,   // (d) tile copied along each plane, plus 13's own pass
    P_SPARSE,      // (e) sparse marks
    P_SCAN,        // (f) next-prime scan, sqrt, fix-ups
    P_SETUP,       // (f) alloc/free, count (first pass), deadline check
    P_TOTAL = 10,
    P_LAST = 15,
    P_N = 16
};
thread_local std::uint64_t pt[P_N];
inline void mark(int slot) {
    const std::uint64_t t = __rdtsc();
    pt[slot] += t - pt[P_LAST];
    pt[P_LAST] = t;
}

// Words per step of the streaming loops. Sixteen words is two AVX-512 or four AVX2 vectors,
// enough independent loads and stores to keep the core busy.
constexpr int W = 16;
// Primes fused into one pass over a plane: six with AVX-512, eight otherwise.
#if defined(__AVX512F__)
constexpr int G = 6;
#else
constexpr int G = 8;
#endif
// A step of W words as one value. GCC's vector extension (also in Clang) splits it into
// whatever vector registers the target has: two with AVX-512, four with AVX2 or eight with
// SSE or NEON.
// Blocks are read and written with memcpy, which allows any 8-byte-aligned position in a Word
// array and compiles to unaligned vector moves. (Clang ignores an aligned(8) on the vector
// type alias and emits aligned moves, which fault on positions that are not 64-byte aligned.)
using Block = Word __attribute__((vector_size(W * sizeof(Word))));
inline Block load(const Word* p) {
    Block b;
    std::memcpy(&b, p, sizeof b);
    return b;
}
inline void store(Word* p, Block b) { std::memcpy(p, &b, sizeof b); }

constexpr int DenseMax = 256;         // primes below this are applied as word patterns
constexpr int RowWords = DenseMax + 2 * W;   // a pattern's period plus one step, rounded up

constexpr std::array<int, 8> Res = {1, 7, 11, 13, 17, 19, 23, 29};
// Plane index of n % 30, or -1 when n shares a factor with 30.
constexpr std::array<int, 30> Plane = {-1, 0,  -1, -1, -1, -1, -1, 1,  -1, -1,
                                       -1, 2,  -1, 3,  -1, -1, -1, 4,  -1, 5,
                                       -1, -1, -1, 6,  -1, -1, -1, -1, -1, 7};
// Multiplicative inverse mod 30, for residues coprime to 30.
constexpr std::array<unsigned, 30> Inv30 = {0, 1,  0, 0, 0,  0, 0,  13, 0, 0, 0, 11, 0, 7, 0,
                                            0, 0, 23, 0, 19, 0, 0, 0, 17, 0, 0, 0, 0,  0, 29};

// First bit index in plane R of a multiple p*k with k >= kmin.
inline std::size_t start_bit(unsigned p, unsigned r, unsigned kmin) {
    const unsigned kr = (r * Inv30[p % 30]) % 30;                      // k = kr (mod 30)
    const unsigned k = kmin + (kr + 30 - kmin % 30) % 30;
    return (std::size_t(p) * k - r) / 30;
}

// Word patterns for a group of up to G primes, built once and shared by all eight planes.
// Row j holds member j's base pattern: a bit at every multiple of p across one period of p
// words, extended to L + W words, where the period L is a multiple of p of at least W words.
// Any bit offset of a stride-p pattern is a whole-word rotation of the base pattern, since 64
// is invertible mod p; tab[j][t] is the rotation that puts a multiple at bit offset t.
struct Group {
    int n;
    std::array<std::int64_t, G> period;
    std::array<std::array<std::int16_t, 64>, G> tab;
    alignas(64) Word rows[G][RowWords];

    void build(const int* primes, int count) {
        n = count;
        for (int j = 0; j < G; j++) {
            Word* row = rows[j];
            if (j >= count) {                    // an unused member: an empty pattern
                period[j] = W;
                std::fill_n(row, 2 * W, Word{0});
                continue;
            }
            const int p = primes[j];
            int L = p;
            while (L < W) L += p;
            period[j] = L;
            std::fill_n(row, p, Word{0});
            for (int b = 0; b < 64 * p; b += p) {
                row[b >> 6] |= Word{1} << (b & 63);
                tab[j][b & 63] = std::int16_t(b >> 6);
            }
            for (int k = p; k < L + W; k++) row[k] = row[k - p];
        }
    }
};

// The sieve class: the whole state of one sieve. A new instance is made for every pass.
class Sieve {
public:
    explicit Sieve(std::uint64_t size)
        : size_(size),
          mbits_(std::size_t(size / 30) + 1),
          nw_((mbits_ + 63) / 64),
          pw_((nw_ + W - 1 + 7) & ~std::size_t{7}) {     // room for a step past nw, 64-byte rows
        void* p = nullptr;
        if (posix_memalign(&p, 64, 8 * pw_ * sizeof(Word)) != 0) throw std::bad_alloc();
        bits_.reset(static_cast<Word*>(p));
    }

    void run() {
        mark(P_SETUP);
        wheel_tile();

        // 13 on its own. Afterwards every bit below 17 * 17 is final.
        constexpr int thirteen[1] = {13};
        dense_primes(thirteen, 1);

        // The remaining primes up to sqrt(size): small ones as fused pattern groups, large
        // ones as strided bit sets. A candidate is only read once every prime up to its square
        // root has been applied: c < g0 * g0 for the smallest prime g0 still pending.
        std::uint64_t q = std::uint64_t(std::sqrt(double(size_)));
        while ((q + 1) * (q + 1) <= size_) q++;
        while (q * q > size_) q--;
        int pending[G];
        int n = 0;
        for (int c = 17; std::uint64_t(c) <= q; c += 2) {
            if (Plane[c % 30] < 0) continue;
            if (n > 0 && (c >= DenseMax || c >= pending[0] * pending[0])) {
                dense_primes(pending, n);
                n = 0;
            }
            if (is_composite(c)) continue;
            if (c < DenseMax) {
                pending[n++] = c;
                if (n == G) {
                    dense_primes(pending, n);
                    n = 0;
                }
            } else {
                sparse_prime(c);
            }
        }
        if (n > 0) dense_primes(pending, n);
        mark(P_SCAN);
    }

    // Primes up to and including size: clear bits for numbers <= size, plus 2, 3 and 5.
    std::uint64_t count() const {
        std::uint64_t c = (size_ >= 2) + (size_ >= 3) + (size_ >= 5);
        for (int pl = 0; pl < 8; pl++) {
            if (size_ < std::uint64_t(Res[pl])) continue;
            const Word* w = plane(pl);
            const std::size_t mmax = (size_ - Res[pl]) / 30;           // last bit <= size
            for (std::size_t k = 0; k < nw_ && 64 * k <= mmax; k++) {
                Word x = ~w[k];
                if (64 * k + 63 > mmax) x &= ~Word{0} >> (63 - (mmax - 64 * k));
                c += std::popcount(x);
            }
        }
        return c;
    }

private:
    struct Free {
        void operator()(void* p) const { std::free(p); }
    };

    Word* plane(int pl) { return bits_.get() + pl * pw_; }
    const Word* plane(int pl) const { return bits_.get() + pl * pw_; }

    bool is_composite(int n) const {
        const std::size_t m = n / 30;
        return (plane(Plane[n % 30])[m / 64] >> (m % 64)) & 1;
    }

    // Multiples of 7 and 11 repeat every 77 words in every plane. Mark one period, starting
    // from 7 and 11 themselves so it is exactly periodic, and copy it along the plane. Then
    // unmark 7 and 11 and mark 1.
    void wheel_tile() {
        const std::size_t t = std::min<std::size_t>(77, nw_);
        constexpr int tile_primes[2] = {7, 11};
        group_->build(tile_primes, 2);
        mark(P_TILE_BUILD);
        for (int pl = 0; pl < 8; pl++) {
            Word* __restrict w = plane(pl);
            const std::size_t first[G] = {start_bit(7, Res[pl], 1), start_bit(11, Res[pl], 1)};
            mark(P_SO_TILE);
            std::fill_n(w, std::min(t + W - 1, pw_), Word{0});   // the tile and its overrun
            apply_group<2>(w, t, *group_, first);
            mark(P_TILE_BUILD);
            for (std::size_t base = t; base < nw_; base += t)
                std::memcpy(w + base, w, std::min(t, nw_ - base) * sizeof(Word));
            std::fill(w + nw_, w + pw_, Word{0});                  // padding past the plane
            mark(P_TILE_COPY);
        }
        plane(0)[0] |= 1;                                             // 1 is not prime
        plane(1)[0] &= ~Word{1};                                   // 7 is prime
        plane(2)[0] &= ~Word{1};                                   // 11 is prime
    }

    // Fused pass over one plane for N members: each step of W words is loaded and stored once
    // while every member's pattern is OR'd in. first[j] is member j's first bit in this plane.
    // The last step runs past nw into the padding, where the extra words get the members' own
    // patterns, which is harmless. N is a template parameter, so each member's phase and period
    // are fixed-size locals that the compiler keeps in registers.
    template <int N>
    static void apply_group(Word* __restrict w, std::size_t nw, const Group& g,
                            const std::size_t* first) {
        // Every member starts at the earliest member's first word, so no member needs a
        // lead-in. A member then also marks its multiples below p * p, which are composite,
        // and p itself, which dense_primes clears again.
        std::size_t start = nw;
        for (int j = 0; j < N; j++) start = std::min(start, first[j] / 64);
        std::size_t r[N], period[N];             // phase in each member's row, and its wrap
        for (int j = 0; j < N; j++) {
            period[j] = std::size_t(g.period[j]);
            const std::size_t back = (first[j] / 64 - start) % period[j];
            const std::size_t t = std::size_t(g.tab[j][first[j] % 64]);
            r[j] = t >= back ? t - back : t + period[j] - back;
        }
        for (std::size_t k = start; k < nw; k += W) {
            Block v = load(w + k);
            for (int j = 0; j < N; j++) {
                v |= load(g.rows[j] + r[j]);
                r[j] += W;
                if (r[j] >= period[j]) r[j] -= period[j];
            }
            store(w + k, v);
        }
    }

    // apply_group with the member count as a compile-time constant.
    template <int... N>
    static void apply_n(int n, Word* w, std::size_t nw, const Group& g, const std::size_t* first,
                        std::integer_sequence<int, N...>) {
        ((n == N + 1 ? apply_group<N + 1>(w, nw, g, first) : void()), ...);
    }
    static void apply(Word* w, std::size_t nw, const Group& g, const std::size_t* first) {
        apply_n(g.n, w, nw, g, first, std::make_integer_sequence<int, G>{});
    }

    // One pattern into a plane from bit b on, for a prime that runs alone; the first word is
    // masked so nothing below bit b is touched.
    static void apply_one(Word* __restrict w, std::size_t nw, const Word* __restrict pat,
                          std::int64_t period, std::int64_t r, std::size_t b) {
        std::size_t k = b / 64;
        if (k >= nw) return;
        w[k] |= pat[r] & (~Word{0} << (b % 64));
        if (++r == period) r = 0;
        for (k++; k < nw; k += W) {
            store(w + k, load(w + k) | load(pat + r));
            r += W;
            if (r >= period) r -= period;
        }
    }

    // Apply a group of primes, from p * p on, to all eight planes.
    void dense_primes(const int* primes, int n) {
        Group& g = *group_;
        const bool lone = n == 1;   // 13: charged to the tile phases, as ISPC folds it there
        mark(P_SCAN);
        g.build(primes, n);
        mark(lone ? P_TILE_BUILD : P_PAT);
        std::size_t ff[8][G];
        for (int pl = 0; pl < 8; pl++)
            for (int j = 0; j < n; j++) ff[pl][j] = start_bit(primes[j], Res[pl], primes[j]);
        mark(lone ? P_SO_TILE : P_SO_DENSE);
        for (int pl = 0; pl < 8; pl++) {
            const std::size_t* first = ff[pl];
            if (n == 1) {      // a lone prime (13): skip the fused loop and its empty members
                apply_one(plane(pl), nw_, g.rows[0], g.period[0], g.tab[0][first[0] % 64],
                          first[0]);
            } else {
                apply(plane(pl), nw_, g, first);
            }
        }
        if (n == 1) { mark(P_TILE_COPY); return; }
        for (int j = 0; j < n; j++) {                  // apply_group marked each member itself
            const std::size_t m = primes[j] / 30;
            if (m < mbits_) plane(Plane[primes[j] % 30])[m / 64] &= ~(Word{1} << (m % 64));
        }
        mark(P_GROUP);
    }

    // A large prime sets at most one bit per word. S planes advance together in one loop,
    // giving S independent read-modify-write streams. Four streams keep every index in a
    // register; with eight, GCC spilled them and the sparse phase ran about 40% slower.
    template <int S>
    static void sparse_streams(Word* __restrict base, std::size_t p, const std::size_t* first,
                               const std::size_t* end) {
        std::size_t i[S];
        std::size_t rounds = ~std::size_t{0};  // rounds in which all S streams are inside
        for (int s = 0; s < S; s++) {
            i[s] = first[s];
            rounds = std::min(rounds, first[s] < end[s] ? (end[s] - 1 - first[s]) / p + 1 : 0);
        }
        for (const std::size_t stop = i[0] + rounds * p; i[0] < stop;) {
            for (int s = 0; s < S; s++) {
                base[i[s] / 64] |= Word{1} << (i[s] % 64);
                i[s] += p;
            }
        }
        for (int s = 0; s < S; s++)
            for (std::size_t x = i[s]; x < end[s]; x += p) base[x / 64] |= Word{1} << (x % 64);
    }

    void sparse_prime(std::size_t p) {
        std::size_t first[8], end[8];        // bit indices within the whole buffer
        mark(P_SCAN);
        for (int pl = 0; pl < 8; pl++) {
            first[pl] = start_bit(unsigned(p), Res[pl], unsigned(p)) + pl * pw_ * 64;
            end[pl] = pl * pw_ * 64 + mbits_;
        }
        mark(P_SO_SPARSE);
        sparse_streams<4>(bits_.get(), p, first, end);
        sparse_streams<4>(bits_.get(), p, first + 4, end + 4);
        mark(P_SPARSE);
    }

    std::uint64_t size_;
    std::size_t mbits_;    // bits used per plane
    std::size_t nw_;       // words used per plane
    std::size_t pw_;       // plane stride in words
    std::unique_ptr<Word[], Free> bits_;           // the eight bit-planes, pw_ words apart
    std::unique_ptr<Group> group_{new Group};      // pattern scratch space (not zeroed)
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

Result worker(Clock::time_point deadline) {
    Result r;
    for (int i = 0; i < P_N; i++) pt[i] = 0;
    const std::uint64_t t0 = __rdtsc();
    pt[P_LAST] = t0;
    while (Clock::now() < deadline) {
        Sieve s(SieveSize);
        s.run();
        if (r.passes == 0) r.count = s.count();
        r.passes++;
    }
    mark(P_SETUP);
    pt[P_TOTAL] = __rdtsc() - t0;
    return r;
}

void report(std::uint64_t passes, Clock::duration elapsed, unsigned threads) {
    std::printf("cauldnz-cpp-wheel;%llu;%f;%u;algorithm=wheel,faithful=yes,bits=1\n",
                static_cast<unsigned long long>(passes),
                std::chrono::duration<double>(elapsed).count(), threads);
    std::fflush(stdout);
}

[[noreturn]] void fail_count() {
    std::fputs("ERROR: wrong prime count\n", stderr);
    std::exit(1);
}

void run_threads(unsigned n) {
    const auto start = Clock::now();
    const auto deadline = start + RunTime;
    std::vector<Result> results(n);
    std::vector<std::thread> threads;
    threads.reserve(n);
    for (unsigned t = 0; t < n; t++)
        threads.emplace_back([&results, t, deadline] { results[t] = worker(deadline); });
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

// PRIMES_TEST=1: prime counts at every power of ten to 10^8.
// PRIMES_TEST=2: the count for every size to 5,000, then every 997th to 400,000.
[[noreturn]] void self_test(int mode) {
    if (mode == 2) {
        for (std::uint64_t n = 1; n < 400'000; n = (n < 5'000) ? n + 1 : n + 997) {
            Sieve s(n);
            s.run();
            std::printf("%llu %llu\n", static_cast<unsigned long long>(n),
                        static_cast<unsigned long long>(s.count()));
        }
        std::exit(0);
    }
    constexpr std::pair<std::uint64_t, std::uint64_t> cases[] = {
        {10, 4}, {100, 25}, {1'000, 168}, {10'000, 1'229}, {100'000, 9'592},
        {1'000'000, 78'498}, {10'000'000, 664'579}, {100'000'000, 5'761'455}};
    int bad = 0;
    for (auto [size, expect] : cases) {
        Sieve s(size);
        s.run();
        const std::uint64_t c = s.count();
        std::printf("size %llu -> %llu primes (expected %llu) %d\n",
                    static_cast<unsigned long long>(size), static_cast<unsigned long long>(c),
                    static_cast<unsigned long long>(expect), c == expect ? 1 : 0);
        if (c != expect) bad = 1;
    }
    std::exit(bad);
}

}  // namespace

int main() {
    if (const char* t = std::getenv("PRIMES_TEST"); t != nullptr && std::atoi(t) != 0)
        self_test(std::atoi(t));

    const auto start = Clock::now();
    const Result r = worker(start + RunTime);
    const auto elapsed = Clock::now() - start;
    if (r.count != Expected) fail_count();
    report(r.passes, elapsed, 1);
    {   // DIAGNOSTIC: phase split of the 1-thread run, TSC cycles per pass and share of total
        const double np = double(r.passes), tot = double(pt[P_TOTAL]);
        double v[10], sum = 0;
        for (int i = 0; i < 10; i++) sum += v[i] = double(pt[i]);
        auto line = [&](const char* name, double c) {
            std::printf("phase;%s;%f;%f\n", name, c / np, 100.0 * c / tot);
        };
        line("start_offsets", v[0] + v[1] + v[2]);
        line("pattern_build", v[3]);
        line("group_passes", v[5]);
        line("tile", v[4] + v[6]);
        line("sparse_marks", v[7]);
        line("scan_setup", v[8] + v[9]);
        std::printf("phase;total;%f;%f\n", tot / np, 100.0 * sum / tot);
        line("detail.start_offsets_dense", v[0]);
        line("detail.start_offsets_sparse", v[1]);
        line("detail.start_offsets_tile", v[2]);
        line("detail.tile_build", v[4]);
        line("detail.tile_copy", v[6]);
        line("detail.scan", v[8]);
        line("detail.setup_alloc_count", v[9]);
        std::fflush(stdout);
    }

    // One independent sieve per thread at all, half and a quarter of the available CPUs:
    // where SMT siblings share an L1, fewer threads can complete more passes.
    const unsigned cpus = available_cpus();
    for (unsigned n = cpus; n >= 2 && n * 4 >= cpus; n /= 2) run_threads(n);
    return 0;
}
