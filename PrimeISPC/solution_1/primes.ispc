// Prime sieve drag race - ISPC (Intel(r) Implicit SPMD Program Compiler) solution by cauldnz.
//
// Sieve of Eratosthenes on a mod-30 wheel. Only numbers coprime to 30 are stored, as 8
// bit-planes, one per residue R in {1,7,11,13,17,19,23,29}; bit m of plane R stands for the
// number 30m+R, and a set bit means composite. Within one plane the multiples of a prime p
// form a plain stride-p progression, so every (prime, plane) pair is an ordinary bit-stride
// sieve whose word pattern repeats every p words. Those repeating patterns are what the
// SIMD lanes stream into the sieve.
//
// The whole program - entry point, timing loop, threads, sieve and output - is ISPC.
// The only external calls are to the C library (clock, allocation, pthreads).

// ---------------------------------------------------------------------------------------
// C library
// ---------------------------------------------------------------------------------------
struct timespec { int64 tv_sec; int64 tv_nsec; };
extern "C" uniform int clock_gettime(uniform int clk, uniform timespec * uniform ts);
extern "C" void * uniform aligned_alloc(uniform int64 align, uniform int64 sz);
extern "C" void free(void * uniform p);
extern "C" uniform int pthread_create(uniform int64 * uniform tid, void * uniform attr,
                                      void * uniform fn, void * uniform arg);
extern "C" uniform int pthread_join(uniform int64 tid, void * uniform * uniform ret);
extern "C" uniform int get_nprocs();
extern "C" int8 * uniform getenv(const uniform int8 * uniform name);
extern "C" uniform int atoi(const uniform int8 * uniform s);
extern "C" void exit(uniform int code);
extern "C" uniform int64 write(uniform int fd, const void * uniform buf, uniform int64 n);

// Report a wrong result on stderr (ISPC's print() only writes to stdout) and stop.
static void fail_count() {
    uniform int8 msg[26] = {69,82,82,79,82,58,32,119,114,111,110,103,32,112,114,105,109,101,
                            32,99,111,117,110,116,10,0};             // "ERROR: wrong prime count\n"
    write(2, msg, 25);
    exit(1);
}

static inline uniform double now() {
    uniform timespec ts;
    clock_gettime(1, &ts);   // CLOCK_MONOTONIC
    return (uniform double)ts.tv_sec + 1e-9 * (uniform double)ts.tv_nsec;
}

// ---------------------------------------------------------------------------------------
// Wheel constants
// ---------------------------------------------------------------------------------------
#define G 8              // prime patterns fused into one pass over a plane
#define MAXPAT 1024      // largest prime handled as a word pattern

static const uniform int RES[8] = {1, 7, 11, 13, 17, 19, 23, 29};
// plane index of n % 30, or -1 when n shares a factor with 30
static const uniform int PLANE[30] = {-1,0,-1,-1,-1,-1,-1,1,-1,-1,-1,2,-1,3,-1,-1,-1,4,-1,5,
                                      -1,-1,-1,6,-1,-1,-1,-1,-1,7};
// multiplicative inverse mod 30, for residues coprime to 30
static const uniform int INV30[30] = {0,1,0,0,0,0,0,13,0,0,0,11,0,7,0,0,0,23,0,19,
                                      0,0,0,17,0,0,0,0,0,29};

// ---------------------------------------------------------------------------------------
// The sieve "class": a struct holding all of a sieve's state, plus the functions below that
// take it as their first argument. A fresh instance is created for every pass.
// ---------------------------------------------------------------------------------------

// Patterns for a group of up to G primes, built once and shared by all 8 planes.
struct Group {
    uniform int n;
    uniform int L[G];                       // pattern period in words
    uniform int16 tab[G][64];               // starting phase for each bit offset
    const uniform uint64 * uniform pp[G];   // pattern for each member
    uniform uint64 zero[64];                // empty pattern for unused members
    uniform uint64 buf[G][MAXPAT + 64];
};

struct Sieve {
    uniform int64 size;              // find primes up to and including this number
    uniform int mbits;               // bits used per plane
    uniform int nw;                  // words used per plane
    uniform int pw;                  // plane stride in words (64-byte aligned)
    uniform int dense_max;           // primes below this are applied as word patterns
    uniform uint64 * uniform bits;   // the 8 bit-planes, pw words apart
    uniform Group * uniform grp;     // pattern scratch space
};

static void sieve_create(uniform Sieve * uniform s, uniform int64 size, uniform int dense_max) {
    s->size = size;
    s->mbits = (uniform int)(size / 30) + 1;
    s->nw = (s->mbits + 63) >> 6;
    s->pw = (s->nw + 7) & ~7;
    s->dense_max = min(dense_max, MAXPAT);
    s->bits = (uniform uint64 * uniform)aligned_alloc(64, (uniform int64)8 * s->pw * 8);
    s->grp = (uniform Group * uniform)aligned_alloc(64, ((sizeof(uniform Group) + 63) / 64) * 64);
    foreach (k = 0 ... 64) s->grp->zero[k] = 0;
}

static void sieve_destroy(uniform Sieve * uniform s) {
    free(s->grp);
    free(s->bits);
}

// First bit index in plane R of a multiple p*k with k >= kmin.
static inline uniform int start_bit(uniform int p, uniform int R, uniform int kmin) {
    uniform int kr = (R * INV30[p % 30]) % 30;          // k must be = kr (mod 30)
    uniform int k = kmin + ((kr - kmin % 30) + 30) % 30;
    return (p * k - R) / 30;
}

// Base pattern for p: a bit at every j = 0 (mod p) across one period of p words, extended to
// L + programCount words. L is a multiple of p that is >= programCount, so advancing the
// phase by programCount needs only one conditional subtract.
// Any bit offset of a stride-p pattern is a whole-word rotation of this base pattern, since
// 64 is invertible mod p. tab[t] records the word whose bit t is set (the 64 multiples in
// one period hit 64 distinct bit positions), which is the starting phase for offset t.
static inline uniform int build_pattern(uniform uint64 * uniform pat, uniform int16 * uniform tab,
                                        uniform int p) {
    uniform int L = p;
    while (L < programCount) L += p;
    foreach (k = 0 ... p) pat[k] = 0;
    for (uniform int j = 0; j < (p << 6); j += p) {
        pat[j >> 6] |= ((uniform uint64)1) << (j & 63);
        tab[j & 63] = (uniform int16)(j >> 6);
    }
    for (uniform int k = p; k < L + programCount; k++) pat[k] = pat[k - p];
    return L;
}

static inline void build_group(uniform Group * uniform g, const uniform int * uniform primes,
                               uniform int n) {
    g->n = n;
    for (uniform int j = 0; j < G; j++) {
        if (j < n) {
            g->L[j] = build_pattern(g->buf[j], g->tab[j], primes[j]);
            g->pp[j] = g->buf[j];
        } else {
            g->L[j] = programCount;
            g->pp[j] = g->zero;
        }
    }
}

// OR one pattern into words [b>>6, wend), starting at phase r; the first word is masked so
// nothing below bit b is touched. Returns the phase of word wend.
static inline uniform int apply_range(uniform uint64 * uniform w, const uniform uint64 * uniform pat,
                                      uniform int L, uniform int r, uniform int b, uniform int wend) {
    uniform int w0 = b >> 6;
    if (w0 >= wend) return r;
    w[w0] |= pat[r] & (~((uniform uint64)0) << (b & 63));
    r += 1; r = (r >= L) ? r - L : r;
    uniform int k = w0 + 1;
    for (; k + programCount <= wend; k += programCount) {
        w[k + programIndex] |= pat[r + programIndex];
        r += programCount;
        r = (r >= L) ? r - L : r;
    }
    if (k + programIndex < wend) w[k + programIndex] |= pat[r + programIndex];
    r += wend - k; r = (r >= L) ? r - L : r;
    return r;
}

// Fused pass over one plane: every group member is OR'd in with a single load and store of
// each sieve word. b[j] is member j's first bit in this plane.
static void apply_group(uniform uint64 * uniform w, uniform int nw,
                        const uniform Group * uniform g, const uniform int * uniform b) {
    uniform int n = g->n;
    uniform int r[G];
    uniform int start = 0;
    for (uniform int j = 0; j < n; j++) start = max(start, (b[j] >> 6) + 1);
    start = min(start, nw);
    for (uniform int j = 0; j < G; j++) {
        if (j < n) {
            uniform int r0 = g->tab[j][b[j] & 63];
            r[j] = apply_range(w, g->pp[j], g->L[j], r0, b[j], start);   // lead-in
        } else r[j] = 0;
    }
    uniform int k = start;
    for (; k + programCount <= nw; k += programCount) {
        uint64 v = w[k + programIndex];
        for (uniform int j = 0; j < G; j++) {
            v |= g->pp[j][r[j] + programIndex];
            uniform int t = r[j] + programCount;
            r[j] = (t >= g->L[j]) ? t - g->L[j] : t;
        }
        w[k + programIndex] = v;
    }
    if (k + programIndex < nw) {
        uint64 v = w[k + programIndex];
        for (uniform int j = 0; j < G; j++) v |= g->pp[j][r[j] + programIndex];
        w[k + programIndex] = v;
    }
}

// Apply a group of primes, from p*p on, to all 8 planes.
static void dense_primes(uniform Sieve * uniform s, const uniform int * uniform primes,
                         uniform int n) {
    build_group(s->grp, primes, n);
    uniform int b[G];
    for (uniform int pl = 0; pl < 8; pl++) {
        for (uniform int j = 0; j < n; j++) b[j] = start_bit(primes[j], RES[pl], primes[j]);
        if (n == 1) {      // a lone prime (13): skip the fused loop and its G-1 empty patterns
            apply_range(s->bits + pl * s->pw, s->grp->pp[0], s->grp->L[0],
                        s->grp->tab[0][b[0] & 63], b[0], s->nw);
            continue;
        }
        apply_group(s->bits + pl * s->pw, s->nw, s->grp, b);
    }
}

// Large primes: at most one bit per word. All 8 planes advance in one loop, giving 8
// independent read-modify-write streams per iteration.
static void sparse_prime(uniform Sieve * uniform s, uniform int p) {
    uniform int nbits = s->mbits, pw = s->pw;
    uniform uint64 * uniform base = s->bits;
    uniform int64 i[8];                            // 64-bit, so no sign extension per OR
    uniform int hi = 0;
    for (uniform int pl = 0; pl < 8; pl++) {
        uniform int sb = start_bit(p, RES[pl], p);
        hi = max(hi, sb);
        i[pl] = sb + (uniform int64)pl * pw * 64;  // bit index within the whole buffer
    }
    // rounds in which all 8 streams are still inside their plane
    uniform int rounds = (hi < nbits) ? (nbits - 1 - hi) / p + 1 : 0;
    for (uniform int k = 0; k < rounds; k++) {
        for (uniform int pl = 0; pl < 8; pl++) {
            base[i[pl] >> 6] |= ((uniform uint64)1) << (i[pl] & 63);
            i[pl] += p;
        }
    }
    for (uniform int pl = 0; pl < 8; pl++) {
        uniform int64 end = (uniform int64)pl * pw * 64 + nbits;
        for (uniform int64 x = i[pl]; x < end; x += p) base[x >> 6] |= ((uniform uint64)1) << (x & 63);
    }
}

static inline uniform bool is_composite(const uniform Sieve * uniform s, uniform int n) {
    uniform int m = n / 30;
    const uniform uint64 * uniform w = s->bits + PLANE[n % 30] * s->pw;
    return ((w[m >> 6] >> (m & 63)) & 1) != 0;
}

static void run_sieve(uniform Sieve * uniform s) {
    uniform int nw = s->nw, pw = s->pw;

    // Phase 1: wheel tile. Multiples of 7 and 11 repeat every 77 words in every plane, so
    // mark one period (starting from 7 and 11 themselves, which keeps it exactly periodic)
    // and copy it along the plane. 7 and 11 are then unmarked.
    uniform int t = min(77, nw);
    uniform int tp[2] = {7, 11};
    build_group(s->grp, tp, 2);
    for (uniform int pl = 0; pl < 8; pl++) {
        uniform uint64 * uniform w = s->bits + pl * pw;
        foreach (k = 0 ... t) w[k] = 0;
        uniform int tb[2];
        tb[0] = start_bit(7, RES[pl], 1);
        tb[1] = start_bit(11, RES[pl], 1);
        apply_group(w, t, s->grp, tb);
        for (uniform int base = t; base < nw; base += t) {
            uniform int n = min(t, nw - base);
            foreach (k = 0 ... n) w[base + k] = w[k];
        }
    }
    s->bits[0]      |= (uniform uint64)1;          // 1 is not prime (plane 1, bit 0)
    s->bits[1 * pw] &= ~((uniform uint64)1);       // 7 is prime
    s->bits[2 * pw] &= ~((uniform uint64)1);       // 11 is prime

    // Phase 2: 13 on its own. Afterwards every bit below 17*17 is final.
    uniform int thirteen[1] = {13};
    dense_primes(s, thirteen, 1);

    // Phase 3: the remaining primes up to sqrt(size), small ones as fused pattern groups and
    // large ones as strided bit sets. A candidate is only read once every prime up to its
    // square root has been applied: c < g0*g0 for the smallest prime g0 still pending.
    uniform int q = (uniform int)sqrt((uniform double)s->size);
    while ((uniform int64)(q + 1) * (q + 1) <= s->size) q++;
    while ((uniform int64)q * q > s->size) q--;
    uniform int dm = s->dense_max;
    uniform int grp[G];
    uniform int n = 0;
    for (uniform int c = 17; c <= q; c += 2) {
        if (PLANE[c % 30] < 0) continue;
        if (n > 0 && (c >= dm || c >= grp[0] * grp[0])) { dense_primes(s, grp, n); n = 0; }
        if (is_composite(s, c)) continue;
        if (c < dm) {
            grp[n++] = c;
            if (n == G) { dense_primes(s, grp, n); n = 0; }
        } else {
            sparse_prime(s, c);
        }
    }
    if (n > 0) dense_primes(s, grp, n);
}

// Number of primes up to and including size: unmarked bits for numbers <= size, plus 2, 3, 5.
static uniform int count_primes(const uniform Sieve * uniform s) {
    uniform int64 size = s->size;
    uniform int c = (size >= 2 ? 1 : 0) + (size >= 3 ? 1 : 0) + (size >= 5 ? 1 : 0);
    for (uniform int pl = 0; pl < 8; pl++) {
        if (size < RES[pl]) continue;
        const uniform uint64 * uniform w = s->bits + pl * s->pw;
        uniform int mmax = (uniform int)((size - RES[pl]) / 30);   // last bit <= size
        for (uniform int k = 0; k < s->nw; k++) {
            uniform int lo = k << 6;
            if (lo > mmax) break;
            uniform uint64 x = ~w[k];
            if (lo + 63 > mmax) x &= ~((uniform uint64)0) >> (63 - (mmax - lo));
            c += popcnt(x);
        }
    }
    return c;
}

// ---------------------------------------------------------------------------------------
// Benchmark driver
// ---------------------------------------------------------------------------------------
static const uniform int64 SIEVE_SIZE = 1000000;
static const uniform int EXPECTED = 78498;
static const uniform double RUN_SECONDS = 5.0;

struct Job {
    uniform double deadline;
    uniform int dense_max;
    uniform int64 passes;
    uniform int count;    // prime count from the last pass, for validation
};

// Thread entry point, also called directly for the single-threaded run. A function passed
// to pthread_create is entered without ISPC's execution mask, so the body runs under
// 'unmasked' to switch all SIMD lanes on.
export void * uniform worker(void * uniform arg) {
    unmasked {
        uniform Job * uniform job = (uniform Job * uniform)arg;
        uniform int64 passes = 0;
        uniform int count = 0;
        while (now() < job->deadline) {
            uniform Sieve s;
            sieve_create(&s, SIEVE_SIZE, job->dense_max);
            run_sieve(&s);
            if (passes == 0) count = count_primes(&s);
            sieve_destroy(&s);
            passes++;
        }
        job->passes = passes;
        job->count = count;
    }
    return NULL;
}

static uniform int env_int(const uniform int8 * uniform name, uniform int dflt) {
    int8 * uniform e = getenv(name);
    return (e != NULL) ? atoi(e) : dflt;
}

// PRIMES_TEST=1: check prime counts for powers of ten up to 10^8 and exit.
static void self_test(uniform int dense_max) {
    uniform int64 sizes[9] = {10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 0};
    uniform int expect[9] = {4, 25, 168, 1229, 9592, 78498, 664579, 5761455, 0};
    uniform int bad = 0;
    for (uniform int i = 0; sizes[i] != 0; i++) {
        uniform Sieve s;
        sieve_create(&s, sizes[i], dense_max);
        run_sieve(&s);
        uniform int c = count_primes(&s);
        sieve_destroy(&s);
        print("size % -> % primes (expected %) %\n", sizes[i], c, expect[i],
              c == expect[i] ? 1 : 0);
        if (c != expect[i]) bad = 1;
    }
    exit(bad);
}

static void run_threads(uniform Job * uniform jobs, uniform int64 * uniform tids,
                        uniform int n, uniform int dense_max) {
    uniform double start = now();
    for (uniform int t = 0; t < n; t++) {
        jobs[t].deadline = start + RUN_SECONDS;
        jobs[t].dense_max = dense_max;
        pthread_create(&tids[t], NULL, (void * uniform)worker, &jobs[t]);
    }
    uniform int64 total = 0;
    for (uniform int t = 0; t < n; t++) {
        pthread_join(tids[t], NULL);
        total += jobs[t].passes;
        if (jobs[t].count != EXPECTED) fail_count();
    }
    uniform double elapsed = now() - start;
    print("cauldnz-ispc;%;%;%;algorithm=wheel,faithful=yes,bits=1\n", total, elapsed, n);
}

export uniform int main() {
    uniform int8 n_dense[17] = {80,82,73,77,69,83,95,68,69,78,83,69,95,77,65,88,0}; // PRIMES_DENSE_MAX
    uniform int8 n_test[12] = {80,82,73,77,69,83,95,84,69,83,84,0};                 // PRIMES_TEST
    uniform int dense_max = env_int(n_dense, 256);
    if (env_int(n_test, 0) != 0) self_test(dense_max);

    uniform int nthreads = clamp(get_nprocs(), 1, 1024);
    uniform Job jobs[1024];
    uniform int64 tids[1024];

    // single-threaded
    uniform double start = now();
    jobs[0].deadline = start + RUN_SECONDS;
    jobs[0].dense_max = dense_max;
    worker(&jobs[0]);
    uniform double elapsed = now() - start;
    if (jobs[0].count != EXPECTED) fail_count();
    print("cauldnz-ispc;%;%;1;algorithm=wheel,faithful=yes,bits=1\n", jobs[0].passes, elapsed);

    // One independent sieve per thread at all, half and a quarter of the hardware threads:
    // where SMT siblings share an L1, fewer threads can complete more passes.
    for (uniform int n = nthreads; n >= 2 && n * 4 >= nthreads; n /= 2)
        run_threads(jobs, tids, n, dense_max);
    return 0;
}
