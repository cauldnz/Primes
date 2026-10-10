// Prime sieve drag race - ISPC (Intel(r) Implicit SPMD Program Compiler) solution by cauldnz.
// Base algorithm, faithful, 1 bit per odd number.
//
// The base algorithm: an outer loop that finds the next prime, then clears every one of its
// odd multiples individually. Bit i of the sieve stands for the odd number 2i+1; a set bit
// means composite. In this source every composite is cleared by its own single-bit OR - no
// operation sets more than one composite.
//
// Two clearing routines, both after the approach of mike-barber's Rust and GordonBGood's
// Chapel solutions:
//
//  * Dense (factor < DENSE_LIMIT): the odd multiples of p repeat with a period of p 64-bit
//    words, holding exactly 64 multiples at fixed (word, bit) positions. The routine is
//    instantiated for every odd factor below the limit with the factor as a compile-time
//    constant, so those 64 positions and single-bit masks become immediates. It covers every
//    odd value, not only primes: the program uses no knowledge of which numbers are prime
//    beyond 2 being the only even one. For factors below 119 the same ORs are written per
//    SIMD lane, over a block of consecutive words, so the compiler emits vector ORs with
//    constant masks: the effect LLVM's SLP vectoriser has on the Rust entry's dense resetter.
//  * Sparse (larger factors): the same idea over bytes. 8 multiples repeat every p bytes,
//    each with a fixed bit position; their byte offsets are computed per factor and the 8
//    masks are compile-time constants selected by p mod 16.
//
// The whole program - entry point, timing loop, threads, sieve and output - is ISPC. The only
// external calls are to the C library (clock, allocation, pthreads).

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
extern "C" uniform int sched_getaffinity(uniform int pid, uniform int64 size,
                                        uniform uint64 * uniform mask);
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

#define DENSE_LIMIT 128      // factors below this use the dense routine
#define VEC_LIMIT 119        // ...and the vector form below this (larger ones exceed LLVM's unroll limit)

// ---------------------------------------------------------------------------------------
// The sieve "class": a struct holding all of a sieve's state, plus the functions below that
// take it as their first argument. A fresh instance is created for every pass.
// ---------------------------------------------------------------------------------------
struct Sieve {
    uniform int64 size;              // find primes up to and including this number
    uniform int nbits;               // one bit per odd number 1, 3, 5, ... <= size
    uniform int nwords;
    uniform uint64 * uniform bits;
};

static void sieve_create(uniform Sieve * uniform s, uniform int64 size) {
    s->size = size;
    s->nbits = (uniform int)((size + 1) / 2);
    s->nwords = (s->nbits + 63) >> 6;
    uniform int64 bytes = (((uniform int64)s->nwords * 8 + 63) / 64) * 64;
    s->bits = (uniform uint64 * uniform)aligned_alloc(64, bytes);
#if defined(ISPC_TARGET_NEON)
    foreach (k = 0 ... s->nwords) s->bits[k] = 0;
#else
    // Only word 0 is cleared here, so the scan can read the bit for 3. The first factor the
    // scan finds is always 3, and its dense pass writes every word instead of reading it
    // (clear_dense_vec with INIT), so the rest of the sieve is initialised there.
    s->bits[0] = 0;
#endif
}

static void sieve_destroy(uniform Sieve * uniform s) {
    free(s->bits);
}

static inline uniform bool is_composite_index(const uniform Sieve * uniform s, uniform int i) {
    return ((s->bits[i >> 6] >> (i & 63)) & 1) != 0;
}

// Dense clearing for a compile-time constant odd factor P. Bit P/2 + j*P (j = 0, 1, ...)
// is the odd multiple P*(2j+1). Chunks of P words start at word multiples of P, so within
// every chunk the 64 multiples sit at the same offsets t_j = P/2 + j*P (j = 0..63).
// Clearing starts at the chunk holding P*P; any smaller multiples in that chunk are
// composite too, except P itself, which is restored afterwards.
static inline void clear_dense_from(uniform uint64 * uniform w, uniform int nwords, const uniform int P,
                                    uniform int c) {
    for (; c + P <= nwords; c += P) {
        #pragma unroll
        for (uniform int j = 0; j < 64; j++) {
            const uniform int t = P / 2 + j * P;
            w[c + (t >> 6)] |= ((uniform uint64)1) << (t & 63);    // one composite
        }
    }
    for (uniform int j = 0; j < 64; j++) {                          // partial last chunk
        const uniform int t = P / 2 + j * P;
        if (c + (t >> 6) >= nwords) break;
        w[c + (t >> 6)] |= ((uniform uint64)1) << (t & 63);
    }
    const uniform int f = P / 2;                                    // P itself is prime
    if ((f >> 6) < nwords) w[f >> 6] &= ~(((uniform uint64)1) << (f & 63));
}

static inline void clear_dense(uniform uint64 * uniform w, uniform int nwords, const uniform int P) {
    clear_dense_from(w, nwords, P, ((P * P / 2) / 64 / P) * P);
}

// Vector dense clearing for small factors. A block of programCount chunks (programCount * P
// words, a whole number of vectors) is cleared one vector of consecutive words at a time: each
// composite in the block gets its own single-bit OR, applied in the lane that holds its word.
// With P and programIndex both compile-time constants, LLVM folds a vector's single-bit ORs into
// one constant, as it does for the scalar routine above. Words left over after the last whole
// block go to the scalar routine.
static inline void clear_dense_vec(uniform uint64 * uniform w, uniform int nwords, const uniform int P,
                                   const uniform bool INIT) {
    uniform int c = ((P * P / 2) / 64 / P) * P;
    for (; c + programCount * P <= nwords; c += programCount * P) {
        #pragma unroll
        for (uniform int kb = 0; kb < programCount * P; kb += programCount) {
            const int k = kb + programIndex;                        // word of the block
            uint64 x = INIT ? 0 : w[c + k];                          // INIT: first factor, no load
            const uniform int n0 = (64 * kb - P / 2) / P;          // first composite near these words
            #pragma unroll
            for (uniform int i = 0; i < 64 * programCount / P + 2; i++) {
                const uniform int t = P / 2 + (n0 + i) * P;
                x |= ((t >> 6) == k) ? ((uniform uint64)1) << (t & 63) : 0;   // one composite
            }
            w[c + k] = x;
        }
    }
    if (INIT) for (uniform int k = c; k < nwords; k++) w[k] = 0;   // words after the last block
    clear_dense_from(w, nwords, P, c);
}

#if defined(ISPC_TARGET_NEON)
// NEON form, after the Rust entry's dense resetter. The loop walks a pointer over runs of U
// periods (U * P words): the whole vectors of a run get the vector single-bit ORs above, and
// any words after them get scalar ones. Factors below 16 take U = programCount, so a run is a
// whole number of vectors and its 2P mask vectors still fit in the NEON registers. Larger
// factors take one period a run, as Rust does: about P / 2 mask registers, which fit up to about
// P = 63, plus a scalar tail of one to three words. Either way the loop is q-register loads, ORs
// and stores with 16-byte-aligned offsets from the pointer, which pair into ldp/stp: four
// words in four instructions, where the scalar routine takes eight.
static inline void clear_dense_neon(uniform uint64 * uniform w, uniform int nwords,
                                    const uniform int P) {
    const uniform int U = (P < 16) ? programCount : 1;             // periods per run
    const uniform int B = U * P;                                   // words per run
    const uniform int NV = B / programCount;                       // whole vectors per run
    const uniform int c = ((P * P / 2) / 64 / P) * P;
    uniform uint64 * uniform q = w + c;
    // A run count rather than an end pointer keeps the offsets relative to q itself.
    for (uniform int n = (nwords - c) / B; n > 0; n--, q += B) {
        #pragma unroll
        for (uniform int v = 0; v < NV; v++) {
            const int k = v * programCount + programIndex;          // word of the run
            uint64 x = q[k];
            const uniform int n0 = (64 * programCount * v - P / 2) / P;
            #pragma unroll
            for (uniform int i = 0; i < 64 * programCount / P + 2; i++) {
                const uniform int t = P / 2 + (n0 + i) * P;
                x |= ((t >> 6) == k) ? ((uniform uint64)1) << (t & 63) : 0;   // one composite
            }
            q[k] = x;
        }
        #pragma unroll
        for (uniform int j = 0; j < 64 * U; j++) {                  // words after the vectors
            const uniform int t = P / 2 + j * P;
            if ((t >> 6) >= NV * programCount)
                q[t >> 6] |= ((uniform uint64)1) << (t & 63);       // one composite
        }
    }
    clear_dense_from(w, nwords, P, (uniform int)(q - w));          // the rest, then P itself
}
#endif

// Sparse clearing over bytes for an odd factor p > 16. Chunks of p bytes start at byte
// multiples of p; in each, the 8 multiples sit at bit offsets t_j = p/2 + j*p (j = 0..7).
// Their bit-in-byte positions depend only on p mod 16 (E), so the masks are constants.
static inline void clear_sparse_e(uniform uint8 * uniform bytes, uniform int nbytes,
                                  uniform int p, const uniform int E) {
    uniform int o0 = (p / 2) >> 3,           o1 = (p / 2 + p) >> 3;
    uniform int o2 = (p / 2 + 2 * p) >> 3,   o3 = (p / 2 + 3 * p) >> 3;
    uniform int o4 = (p / 2 + 4 * p) >> 3,   o5 = (p / 2 + 5 * p) >> 3;
    uniform int o6 = (p / 2 + 6 * p) >> 3,   o7 = (p / 2 + 7 * p) >> 3;
    const uniform uint8 m0 = 1 << ((E / 2) & 7),         m1 = 1 << ((E / 2 + E) & 7);
    const uniform uint8 m2 = 1 << ((E / 2 + 2 * E) & 7), m3 = 1 << ((E / 2 + 3 * E) & 7);
    const uniform uint8 m4 = 1 << ((E / 2 + 4 * E) & 7), m5 = 1 << ((E / 2 + 5 * E) & 7);
    const uniform uint8 m6 = 1 << ((E / 2 + 6 * E) & 7), m7 = 1 << ((E / 2 + 7 * E) & 7);
    // Walk a pointer over the chunks: each OR is then one instruction with a register offset.
    // Indexing with a 32-bit chunk offset cost a sign extension and an add per composite.
    uniform uint8 * uniform q = bytes + ((p * p / 2) / 8 / p) * p;
    uniform uint8 * uniform end = bytes + nbytes;
    for (; q + p <= end; q += p) {                                  // one composite each
        q[o0] |= m0; q[o1] |= m1; q[o2] |= m2; q[o3] |= m3;
        q[o4] |= m4; q[o5] |= m5; q[o6] |= m6; q[o7] |= m7;
    }
    if (q + o0 < end) q[o0] |= m0; else return;                     // partial last chunk
    if (q + o1 < end) q[o1] |= m1; else return;
    if (q + o2 < end) q[o2] |= m2; else return;
    if (q + o3 < end) q[o3] |= m3; else return;
    if (q + o4 < end) q[o4] |= m4; else return;
    if (q + o5 < end) q[o5] |= m5; else return;
    if (q + o6 < end) q[o6] |= m6; else return;
    if (q + o7 < end) q[o7] |= m7;
}

static void clear_sparse(uniform Sieve * uniform s, uniform int p) {
    uniform uint8 * uniform b = (uniform uint8 * uniform)s->bits;
    uniform int nbytes = s->nwords * 8;
    switch (p & 15) {
        case 1:  clear_sparse_e(b, nbytes, p, 1);  break;
        case 3:  clear_sparse_e(b, nbytes, p, 3);  break;
        case 5:  clear_sparse_e(b, nbytes, p, 5);  break;
        case 7:  clear_sparse_e(b, nbytes, p, 7);  break;
        case 9:  clear_sparse_e(b, nbytes, p, 9);  break;
        case 11: clear_sparse_e(b, nbytes, p, 11); break;
        case 13: clear_sparse_e(b, nbytes, p, 13); break;
        default: clear_sparse_e(b, nbytes, p, 15); break;
    }
}

#if defined(ISPC_TARGET_NEON)
#define D(P) case P: clear_dense_neon(s->bits, s->nwords, P); break;
#else
#define D(P) case P: if (P < VEC_LIMIT) clear_dense_vec(s->bits, s->nwords, P, P == 3); \
                     else clear_dense(s->bits, s->nwords, P); break;
#endif

// Clear all odd multiples of factor p.
static void clear_factor(uniform Sieve * uniform s, uniform int p) {
    // clear_factor isn't inlined, so ISPC would compile it for an unknown execution mask and
    // mask every vector load and store in the dense code. Callers run with all lanes on.
    unmasked {
        if (p >= DENSE_LIMIT) { clear_sparse(s, p); return; }
        switch (p) {
            D(3)   D(5)   D(7)   D(9)   D(11)  D(13)  D(15)  D(17)  D(19)  D(21)  D(23)  D(25)
            D(27)  D(29)  D(31)  D(33)  D(35)  D(37)  D(39)  D(41)  D(43)  D(45)  D(47)  D(49)
            D(51)  D(53)  D(55)  D(57)  D(59)  D(61)  D(63)  D(65)  D(67)  D(69)  D(71)  D(73)
            D(75)  D(77)  D(79)  D(81)  D(83)  D(85)  D(87)  D(89)  D(91)  D(93)  D(95)  D(97)
            D(99)  D(101) D(103) D(105) D(107) D(109) D(111) D(113) D(115) D(117) D(119) D(121)
            D(123) D(125) D(127)
        }
    }
}

// The base algorithm: find the next prime, clear its multiples, repeat up to sqrt(size).
static void run_sieve(uniform Sieve * uniform s) {
    uniform int q = (uniform int)sqrt((uniform double)s->size);
    while ((uniform int64)(q + 1) * (q + 1) <= s->size) q++;
    while ((uniform int64)q * q > s->size) q--;
    uniform int factor = 3;
    while (factor <= q) {
        uniform int i = factor >> 1;
        while (i < s->nbits && is_composite_index(s, i)) i++;     // next prime
        factor = 2 * i + 1;
        if (factor > q) break;
        clear_factor(s, factor);
        factor += 2;
    }
}

// Number of primes up to and including size: unmarked odd numbers 3..size, plus 2.
static uniform int count_primes(const uniform Sieve * uniform s) {
    if (s->size < 2) return 0;
    uniform int c = 1;                                              // the prime 2
    for (uniform int i = 1; i < s->nbits; i++)                      // bit 0 is the number 1
        if (!is_composite_index(s, i)) c++;
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
    uniform int64 passes;
    uniform int count;    // prime count from the first pass, for validation
    // DIAGNOSTIC: per-thread phase cycles (TSC), summed over the thread's passes.
    uniform int64 p_setup, p_dense, p_sparse, p_scan, p_destroy;
};

// Hardware threads this process may run on: the CPUs in its affinity mask, so a container
// limited with --cpuset-cpus is not oversubscribed. get_nprocs() counts every online CPU.
static uniform int hardware_threads() {
    uniform uint64 mask[16];                                       // up to 1024 CPUs
    for (uniform int i = 0; i < 16; i++) mask[i] = 0;
    if (sched_getaffinity(0, 16 * 8, mask) != 0) return get_nprocs();
    uniform int n = 0;
    for (uniform int i = 0; i < 16; i++) n += popcnt(mask[i]);
    return n > 0 ? n : get_nprocs();
}

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
            sieve_create(&s, SIEVE_SIZE);
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

// PRIMES_TEST=1: check prime counts for 10^1..10^8 (and a few awkward sizes) and exit.
static void self_test() {
    uniform int64 sizes[14] = {1, 2, 3, 10, 100, 1000, 10000, 100000, 1000000, 10000000,
                               100000000, 127, 16383, 0};
    uniform int expect[14] = {0, 1, 2, 4, 25, 168, 1229, 9592, 78498, 664579, 5761455,
                              31, 1900, 0};
    uniform int bad = 0;
    for (uniform int i = 0; i < 13; i++) {
        uniform Sieve s;
        sieve_create(&s, sizes[i]);
        run_sieve(&s);
        uniform int c = count_primes(&s);
        sieve_destroy(&s);
        print("size % -> % primes (expected %) %\n", sizes[i], c, expect[i],
              c == expect[i] ? 1 : 0);
        if (c != expect[i]) bad = 1;
    }
    exit(bad);
}

static void run_threads(uniform Job * uniform jobs, uniform int64 * uniform tids, uniform int n) {
    uniform double start = now();
    for (uniform int t = 0; t < n; t++) {
        jobs[t].deadline = start + RUN_SECONDS;
        pthread_create(&tids[t], NULL, (void * uniform)worker, &jobs[t]);
    }
    uniform int64 total = 0;
    for (uniform int t = 0; t < n; t++) {
        pthread_join(tids[t], NULL);
        total += jobs[t].passes;
        if (jobs[t].count != EXPECTED) fail_count();
    }
    uniform double elapsed = now() - start;
    print("cauldnz-ispc-base;%;%;%;algorithm=base,faithful=yes,bits=1\n", total, elapsed, n);
}

// ---------------------------------------------------------------------------------------
// DIAGNOSTIC (never merged): per-phase cycles per pass at 1, N/4, N/2 and N threads, to see
// which phase stops gaining at scale. TSC via ISPC clock(), so cycles are wall time at the
// TSC rate, not core cycles.
// ---------------------------------------------------------------------------------------
static void run_sieve_prof(uniform Sieve * uniform s, uniform Job * uniform job) {
    uniform int64 r0 = clock();
    uniform int q = (uniform int)sqrt((uniform double)s->size);
    while ((uniform int64)(q + 1) * (q + 1) <= s->size) q++;
    while ((uniform int64)q * q > s->size) q--;
    uniform int factor = 3;
    uniform int64 dense = 0, sparse = 0;
    while (factor <= q) {
        uniform int i = factor >> 1;
        while (i < s->nbits && is_composite_index(s, i)) i++;     // next prime
        factor = 2 * i + 1;
        if (factor > q) break;
        uniform int64 c0 = clock();
        clear_factor(s, factor);
        uniform int64 c1 = clock();
        if (factor < DENSE_LIMIT) dense += c1 - c0; else sparse += c1 - c0;
        factor += 2;
    }
    uniform int64 total = clock() - r0;
    job->p_dense += dense;
    job->p_sparse += sparse;
    job->p_scan += total - dense - sparse;
}

export void * uniform worker_prof(void * uniform arg) {
    unmasked {
        uniform Job * uniform job = (uniform Job * uniform)arg;
        uniform int64 passes = 0;
        job->p_setup = job->p_dense = job->p_sparse = job->p_scan = job->p_destroy = 0;
        while (now() < job->deadline) {
            uniform Sieve s;
            uniform int64 t0 = clock();
            sieve_create(&s, SIEVE_SIZE);
            uniform int64 t1 = clock();
            run_sieve_prof(&s, job);
            uniform int64 t2 = clock();
            sieve_destroy(&s);
            uniform int64 t3 = clock();
            job->p_setup += t1 - t0;
            job->p_destroy += t3 - t2;
            passes++;
        }
        job->passes = passes;
    }
    return NULL;
}

static void profile_threads(uniform Job * uniform jobs, uniform int64 * uniform tids, uniform int n) {
    uniform double start = now();
    for (uniform int t = 0; t < n; t++) {
        jobs[t].deadline = start + RUN_SECONDS;
        pthread_create(&tids[t], NULL, (void * uniform)worker_prof, &jobs[t]);
    }
    uniform int64 passes = 0, su = 0, de = 0, sp = 0, sc = 0, dt = 0;
    for (uniform int t = 0; t < n; t++) {
        pthread_join(tids[t], NULL);
        passes += jobs[t].passes;
        su += jobs[t].p_setup; de += jobs[t].p_dense; sp += jobs[t].p_sparse;
        sc += jobs[t].p_scan; dt += jobs[t].p_destroy;
    }
    uniform double elapsed = now() - start;
    print("cauldnz-ispc-base;mtprofile;%;passes;%;%\n", n, passes, elapsed);
    print("cauldnz-ispc-base;mtprofile;%;setup;%\n", n, su / passes);
    print("cauldnz-ispc-base;mtprofile;%;dense;%\n", n, de / passes);
    print("cauldnz-ispc-base;mtprofile;%;sparse;%\n", n, sp / passes);
    print("cauldnz-ispc-base;mtprofile;%;scan;%\n", n, sc / passes);
    print("cauldnz-ispc-base;mtprofile;%;destroy;%\n", n, dt / passes);
}

export uniform int main() {
    uniform int8 n_test[12] = {80,82,73,77,69,83,95,84,69,83,84,0};    // PRIMES_TEST
    if (env_int(n_test, 0) != 0) self_test();

    uniform int nthreads = clamp(hardware_threads(), 1, 1024);
    uniform Job jobs[1024];
    uniform int64 tids[1024];

    // DIAGNOSTIC: the phase profile at 1, N/4, N/2 and N threads, then the normal run.
    uniform int counts[4] = {1, max(nthreads / 4, 1), max(nthreads / 2, 1), nthreads};
    for (uniform int k = 0; k < 4; k++) profile_threads(jobs, tids, counts[k]);

    uniform double start = now();
    jobs[0].deadline = start + RUN_SECONDS;
    worker(&jobs[0]);
    uniform double elapsed = now() - start;
    if (jobs[0].count != EXPECTED) fail_count();
    print("cauldnz-ispc-base;%;%;1;algorithm=base,faithful=yes,bits=1\n", jobs[0].passes, elapsed);

    // One independent sieve per thread at all, half and a quarter of the hardware threads.
    for (uniform int n = nthreads; n >= 2 && n * 4 >= nthreads; n /= 2)
        run_threads(jobs, tids, n);
    return 0;
}
