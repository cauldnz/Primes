// Prime sieve drag race - ISPC (Intel(r) Implicit SPMD Program Compiler) solution by cauldnz.
//
// Sieve of Eratosthenes on a mod-210 wheel. Only numbers coprime to 210 = 2*3*5*7 are stored,
// as 48 bit-planes, one per residue R in {1,11,13,...,209}; bit m of plane R stands for the
// number 210m+R, and a set bit means composite. Within one plane the multiples of a prime p
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

// ---------------------------------------------------------------------------------------
// Wheel constants
// ---------------------------------------------------------------------------------------
// Prime patterns fused into one pass over a plane. Six suits AVX-512 on Zen 5 (+4.5% at 1T,
// hc-011) but costs AVX2 on Zen 3 (-1.2%), so the AVX2 and SSE builds keep eight.
#if defined(ISPC_TARGET_AVX512SKX)
#define G 6
#else
#define G 8
#endif
#define MAXPAT 1024      // largest prime handled as a word pattern
// Masked vector stores are slow on AVX2 for Zen 2 to Zen 4 (about six cycles each) and cheap
// with AVX-512. Without AVX-512, the group loop runs unmasked and partial vectors run past their
// end into the plane's padding instead.
#if defined(ISPC_TARGET_AVX512SKX)
#define TAIL_OVERRUN 0
#else
#define TAIL_OVERRUN 1
#endif
// Words the fused group loop advances per iteration. With AVX-512 it takes two vectors, 32
// words, so each member's phase update is paid once per 32 words. Patterns then have a period
// of at least STEP words and run STEP words past it.
#if defined(ISPC_TARGET_AVX512SKX)
#define STEP (2 * programCount)
#else
#define STEP programCount
#endif

// The 48 residues mod 210 coprime to 210 (2*3*5*7), in increasing order.
static const uniform int RES[48] = {1,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71,73,79,83,89,97,101,103,107,109,113,
    121,127,131,137,139,143,149,151,157,163,167,169,173,179,181,187,191,193,197,199,209};
// plane index of n % 210, or -1 when n shares a factor with 210
static const uniform int8 PLANE[210] = {
    -1,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,1,-1,2,-1,-1,-1,3,-1,4,-1,-1,-1,5,-1,-1,-1,-1,-1,6,-1,7,
    -1,-1,-1,-1,-1,8,-1,-1,-1,9,-1,10,-1,-1,-1,11,-1,-1,-1,-1,-1,12,-1,-1,-1,-1,-1,13,-1,14,
    -1,-1,-1,-1,-1,15,-1,-1,-1,16,-1,17,-1,-1,-1,-1,-1,18,-1,-1,-1,19,-1,-1,-1,-1,-1,20,-1,
    -1,-1,-1,-1,-1,-1,21,-1,-1,-1,22,-1,23,-1,-1,-1,24,-1,25,-1,-1,-1,26,-1,-1,-1,-1,-1,-1,
    -1,27,-1,-1,-1,-1,-1,28,-1,-1,-1,29,-1,-1,-1,-1,-1,30,-1,31,-1,-1,-1,32,-1,-1,-1,-1,-1,
    33,-1,34,-1,-1,-1,-1,-1,35,-1,-1,-1,-1,-1,36,-1,-1,-1,37,-1,38,-1,-1,-1,39,-1,-1,-1,-1,
    -1,40,-1,41,-1,-1,-1,-1,-1,42,-1,-1,-1,43,-1,44,-1,-1,-1,45,-1,46,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,47};
// half the gap from RES[i] to the next residue coprime to 210 (RES[47] = 209 -> 211)
static const uniform int8 GAPH[48] = {5,1,2,1,2,3,1,3,2,1,2,3,3,1,3,2,1,3,2,3,4,2,1,2,1,2,4,3,2,3,1,2,3,1,3,3,2,1,2,3,1,3,2,1,
    2,1,5,1};

// ---------------------------------------------------------------------------------------
// The sieve "class": a struct holding all of a sieve's state, plus the functions below that
// take it as their first argument. A fresh instance is created for every pass.
// ---------------------------------------------------------------------------------------

// Patterns for a group of up to G primes, built once and shared by all 48 planes.
struct Group {
    uniform int n;
    uniform int L[G];                       // pattern period in words
    uniform int16 tab[G][64];               // starting phase for each bit offset
    const uniform uint64 * uniform pp[G];   // pattern for each member
    uniform uint64 buf[G][MAXPAT + 64];
    uniform int st[G][48];                  // each member's first bit, by plane
};

struct Sieve {
    uniform int64 size;              // find primes up to and including this number
    uniform int mbits;               // bits used per plane
    uniform int nw;                  // words used per plane
    uniform int pw;                  // plane stride in words
    uniform int dense_max;           // primes below this are applied as word patterns
    uniform uint64 * uniform bits;   // the 48 bit-planes, pw words apart
    uniform Group * uniform grp;     // pattern scratch space
};

static void sieve_create(uniform Sieve * uniform s, uniform int64 size, uniform int dense_max) {
    s->size = size;
    s->mbits = (uniform int)(size / 210) + 1;
    s->nw = (s->mbits + 63) >> 6;
    s->pw = s->nw + (TAIL_OVERRUN ? programCount - 1 : 0);   // room to overrun nw
    s->dense_max = min(dense_max, MAXPAT);
    s->bits = (uniform uint64 * uniform)aligned_alloc(64, (((uniform int64)48 * s->pw * 8 + 63) / 64) * 64);
    s->grp = (uniform Group * uniform)aligned_alloc(64, ((sizeof(uniform Group) + 63) / 64) * 64);
}

static void sieve_destroy(uniform Sieve * uniform s) {
    free(s->grp);
    free(s->bits);
}

// First bit of p's multiples from p*p on, in each of the 48 planes, written to st[plane];
// returns the largest. The multiples p*q with q coprime to 210 hit every plane exactly once in
// any 48 consecutive such q, so walk q = p and the next 47 values coprime to 210, keeping
// n = p*q as (n / 210, n % 210). p is split by 210 once; each step then adds a precomputed
// increment (gap*p, split the same way) with a single carry. No division per plane.
static inline uniform int starts48(uniform int p, uniform int * uniform st) {
    uniform unsigned int up = p;
    uniform unsigned int pq = up / 210;
    uniform unsigned int pr = up - pq * 210;
    uniform unsigned int dq[6], dr[6];       // (2k*p) / 210 and % 210, k = 1..5
    dq[0] = 0; dr[0] = 0;
    uniform unsigned int q2 = 2 * pq, r2 = 2 * pr;
    if (r2 >= 210) { r2 -= 210; q2++; }
    for (uniform int k = 1; k <= 5; k++) {
        uniform unsigned int r = dr[k - 1] + r2, q = dq[k - 1] + q2;
        if (r >= 210) { r -= 210; q++; }
        dq[k] = q; dr[k] = r;
    }
    // p*p = 210 (p*pq) + p*pr, with p*pr split by 210 in turn
    uniform unsigned int t = up * pr;
    uniform unsigned int tq = t / 210;
    uniform unsigned int nq = up * pq + tq, nr = t - tq * 210;
    uniform int iq = PLANE[pr];
    uniform int last = 0;
    for (uniform int j = 0; j < 48; j++) {
        st[PLANE[nr]] = (uniform int)nq;
        last = (uniform int)nq;
        uniform int k = GAPH[iq];
        nq += dq[k]; nr += dr[k];
        if (nr >= 210) { nr -= 210; nq++; }
        iq = (iq == 47) ? 0 : iq + 1;
    }
    return last;
}

// Base pattern for p: a bit at every j = 0 (mod p) across one period of p words, extended to
// L + STEP words. L is a multiple of p that is >= STEP, so advancing the phase by up to STEP
// needs only one conditional subtract.
// Any bit offset of a stride-p pattern is a whole-word rotation of this base pattern, since
// 64 is invertible mod p. tab[t] records the word whose bit t is set (the 64 multiples in
// one period hit 64 distinct bit positions), which is the starting phase for offset t.
static inline uniform int build_pattern(uniform uint64 * uniform pat, uniform int16 * uniform tab,
                                        uniform int p) {
    uniform int L = p;
    while (L < STEP) L += p;
    foreach (k = 0 ... p) pat[k] = 0;
    for (uniform int j = 0; j < (p << 6); j += p) {
        pat[j >> 6] |= ((uniform uint64)1) << (j & 63);
        tab[j & 63] = (uniform int16)(j >> 6);
    }
    for (uniform int k = p; k < L + STEP; k++) pat[k] = pat[k - p];
    return L;
}

static inline void build_group(uniform Group * uniform g, const uniform int * uniform primes,
                               uniform int n) {
    g->n = n;
    for (uniform int j = 0; j < G; j++) {
        if (j < n) {
            g->L[j] = build_pattern(g->buf[j], g->tab[j], primes[j]);
            g->pp[j] = g->buf[j];
        } else {                    // an unused member: an empty pattern in its own row
            g->L[j] = STEP;
            foreach (k = 0 ... 2 * STEP) g->buf[j][k] = 0;
            g->pp[j] = g->buf[j];
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
    // The last partial vector. With TAIL_OVERRUN it runs past wend: the extra words get this
    // prime's own pattern, which is correct for them, and past nw they land in padding.
    if (TAIL_OVERRUN) { if (k < wend) w[k + programIndex] |= pat[r + programIndex]; }
    else if (k + programIndex < wend) w[k + programIndex] |= pat[r + programIndex];
    r += wend - k; r = (r >= L) ? r - L : r;
    return r;
}

// Fused pass over one plane: every group member is OR'd in with a single load and store of
// each sieve word. b[j] is member j's first bit in this plane.
static void apply_group(uniform uint64 * uniform w, uniform int nw,
                        const uniform Group * uniform g, const uniform int * uniform b) {
    // Every member starts at the earliest member's first word, so no member needs a lead-in.
    // A member then also marks its multiples below p*p, which are composite, and p itself,
    // which dense_primes clears again.
#if TAIL_OVERRUN
    unmasked {   // callers run with every lane on; without this each store is masked
#endif
    // Patterns are read from their fixed rows of g->buf, not through g->pp, so each member
    // needs only its phase in a register: pointers per member spilled on x86. Phases and
    // periods are 64-bit, so addressing needs no sign extension.
    uniform int n = g->n;
    uniform int64 r[G], L[G];
    uniform int start = nw;
    for (uniform int j = 0; j < n; j++) start = min(start, b[j] >> 6);
    for (uniform int j = 0; j < G; j++) {
        L[j] = g->L[j];
        if (j < n) {
            // (b>>6) - start is below nw, a few periods at most: subtract rather than divide
            uniform int d = (b[j] >> 6) - start;
            while (d >= g->L[j]) d -= g->L[j];
            uniform int r0 = g->tab[j][b[j] & 63] - d;   // phase at start
            r[j] = (r0 < 0) ? r0 + L[j] : r0;
        } else r[j] = 0;
    }
    uniform int64 k = start;
#if defined(ISPC_TARGET_AVX512SKX)
    // Two vectors per iteration and one phase update per member. The callers run with every
    // lane on, so the full vectors need no mask; the loop below takes the rest.
    unmasked {
        for (; k + STEP <= nw; k += STEP) {
            uint64 v0 = w[k + programIndex];
            uint64 v1 = w[k + programCount + programIndex];
            for (uniform int j = 0; j < G; j++) {
                v0 |= g->buf[j][r[j] + programIndex];
                v1 |= g->buf[j][r[j] + programCount + programIndex];
                uniform int64 t = r[j] + STEP;
                r[j] = (t >= L[j]) ? t - L[j] : t;
            }
            w[k + programIndex] = v0;
            w[k + programCount + programIndex] = v1;
        }
    }
#endif
    for (; k + programCount <= nw; k += programCount) {
        uint64 v = w[k + programIndex];
        for (uniform int j = 0; j < G; j++) {
            v |= g->buf[j][r[j] + programIndex];
            uniform int64 t = r[j] + programCount;
            r[j] = (t >= L[j]) ? t - L[j] : t;
        }
        w[k + programIndex] = v;
    }
    if (TAIL_OVERRUN ? k < nw : k + programIndex < nw) {
        uint64 v = w[k + programIndex];
        for (uniform int j = 0; j < G; j++) v |= g->buf[j][r[j] + programIndex];
        w[k + programIndex] = v;
    }
#if TAIL_OVERRUN
    }
#endif
}

// Apply a group of primes, from p*p on, to all 48 planes.
static void dense_primes(uniform Sieve * uniform s, const uniform int * uniform primes,
                         uniform int n) {
    uniform Group * uniform g = s->grp;
    build_group(g, primes, n);
    for (uniform int j = 0; j < n; j++) starts48(primes[j], g->st[j]);
    uniform int b[G];
    for (uniform int pl = 0; pl < 48; pl++) {
        for (uniform int j = 0; j < n; j++) b[j] = g->st[j][pl];
        if (n == 1) {      // a lone prime: skip the fused loop and its G-1 empty patterns
            apply_range(s->bits + pl * s->pw, g->pp[0], g->L[0], g->tab[0][b[0] & 63], b[0], s->nw);
            continue;
        }
        apply_group(s->bits + pl * s->pw, s->nw, g, b);
    }
    if (n == 1) return;
    for (uniform int j = 0; j < n; j++) {          // apply_group marked each member itself
        uniform int m = primes[j] / 210;
        if (m < s->mbits)
            s->bits[PLANE[primes[j] % 210] * s->pw + (m >> 6)] &= ~(((uniform uint64)1) << (m & 63));
    }
}

// Large primes: at most one bit per word. All 48 planes advance in one loop, giving 48
// independent read-modify-write streams per round.
static void sparse_prime(uniform Sieve * uniform s, uniform int p) {
    uniform int nbits = s->mbits, pw = s->pw;
    uniform uint64 * uniform base = s->bits;
    uniform int st[48];
    uniform int hi = starts48(p, st);
    uniform int64 i[48];                           // 64-bit, so no sign extension per OR
    for (uniform int pl = 0; pl < 48; pl++)
        i[pl] = st[pl] + (uniform int64)pl * pw * 64;  // bit index within the whole buffer
    // rounds in which all 48 streams are still inside their plane
    uniform int rounds = (hi < nbits) ? (nbits - 1 - hi) / p + 1 : 0;
    // Eight planes at a time, so the eight stream positions stay in registers.
    const uniform int64 adv = (uniform int64)rounds * p;
    for (uniform int c = 0; c < 48; c += 8) {
        uniform int64 ii[8];
        for (uniform int t = 0; t < 8; t++) ii[t] = i[c + t];
        const uniform int64 lim = ii[0] + adv;          // bounds stream 0; no counter
        while (ii[0] < lim) {
            for (uniform int t = 0; t < 8; t++) {
                base[ii[t] >> 6] |= ((uniform uint64)1) << (ii[t] & 63);
                ii[t] += p;
            }
        }
        for (uniform int t = 0; t < 8; t++) i[c + t] = ii[t];
    }
    // The 48 starts span less than p bits (they come from 48 consecutive q, under 210 apart),
    // so after those rounds each stream has at most one bit left. Set it without a branch:
    // a stream that is done ORs zero into its plane's last word.
    for (uniform int pl = 0; pl < 48; pl++) {
        uniform int64 x = i[pl] - (uniform int64)pl * pw * 64;   // bit within the plane
        uniform bool inside = x < nbits;
        uniform int64 xs = inside ? x : nbits - 1;
        uniform uint64 v = inside ? (((uniform uint64)1) << (x & 63)) : 0;
        base[(uniform int64)pl * pw + (xs >> 6)] |= v;
    }
}

static inline uniform bool is_composite(const uniform Sieve * uniform s, uniform int n) {
    uniform int m = n / 210;
    const uniform uint64 * uniform w = s->bits + PLANE[n % 210] * s->pw;
    return ((w[m >> 6] >> (m & 63)) & 1) != 0;
}

static void run_sieve(uniform Sieve * uniform s) {
    // 2, 3, 5 and 7 are the wheel. Every other prime up to sqrt(size) is applied in turn,
    // small ones as fused pattern groups and large ones as strided bit sets. A candidate is
    // only read once every prime up to its square root has been applied: c < g0*g0 for the
    // smallest prime g0 still pending. Below 11*11 every candidate is prime.
    uniform int64 total = (uniform int64)48 * s->pw;
    foreach (k = 0 ... total) s->bits[k] = 0;
    s->bits[0] |= (uniform uint64)1;               // 1 is not prime (plane 1, bit 0)

    uniform int q = (uniform int)sqrt((uniform double)s->size);
    while ((uniform int64)(q + 1) * (q + 1) <= s->size) q++;
    while ((uniform int64)q * q > s->size) q--;
    uniform int dm = s->dense_max;
    uniform int grp[G];
    uniform int n = 0;
    for (uniform int c = 11; c <= q; c += 2) {
        if (PLANE[c % 210] < 0) continue;
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

// Number of primes up to and including size: unmarked bits for numbers <= size, plus 2, 3, 5, 7.
static uniform int count_primes(const uniform Sieve * uniform s) {
    uniform int64 size = s->size;
    uniform int c = (size >= 2 ? 1 : 0) + (size >= 3 ? 1 : 0) + (size >= 5 ? 1 : 0)
                  + (size >= 7 ? 1 : 0);
    for (uniform int pl = 0; pl < 48; pl++) {
        if (size < RES[pl]) continue;
        const uniform uint64 * uniform w = s->bits + pl * s->pw;
        uniform int mmax = (uniform int)((size - RES[pl]) / 210);   // last bit <= size
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

    uniform int nthreads = clamp(hardware_threads(), 1, 1024);
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
