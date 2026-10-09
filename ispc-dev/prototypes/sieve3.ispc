// Prime sieve drag race - pure ISPC (Intel Implicit SPMD Program Compiler).
// Sieve of Eratosthenes on a mod-30 wheel: only numbers coprime to 30 are stored, as 8
// bit-planes, one per residue R in {1,7,11,13,17,19,23,29}. Bit m of plane R is 30m+R.
// A set bit means composite. Within one plane the multiples of p form a stride-p
// progression, so each (prime, plane) pair is a plain bit-stride sieve that repeats every
// p words; those repeating word patterns are what the SIMD lanes stream.
// Everything is rebuilt from scratch on every pass.

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

static const uniform int64 LIMIT = 1000000;
static const uniform int MAXPAT = 1024;
#define G 8                                  // (prime) patterns fused per sieve pass

static const uniform int RES[8] = {1, 7, 11, 13, 17, 19, 23, 29};
// plane index of n % 30, or -1 when n shares a factor with 30
static const uniform int PLANE[30] = {-1,0,-1,-1,-1,-1,-1,1,-1,-1,-1,2,-1,3,-1,-1,-1,4,-1,5,
                                      -1,-1,-1,6,-1,-1,-1,-1,-1,7};
// multiplicative inverse mod 30 (only meaningful for residues coprime to 30)
static const uniform int INV30[30] = {0,1,0,0,0,0,0,13,0,0,0,11,0,7,0,0,0,23,0,19,
                                      0,0,0,17,0,0,0,0,0,29};

static uniform int dense_max = 256;

static inline uniform double now() {
    uniform timespec ts;
    clock_gettime(1, &ts);
    return (uniform double)ts.tv_sec + 1e-9 * (uniform double)ts.tv_nsec;
}

struct Sieve {
    uniform uint64 * uniform bits;   // 8 planes, each pw words apart
    uniform int mbits;               // bits used per plane
    uniform int nw;                  // words used per plane
    uniform int pw;                  // plane stride in words (64-byte aligned)
};

// First bit index in plane R of a multiple p*k with k >= kmin.
static inline uniform int start_bit(uniform int p, uniform int R, uniform int kmin) {
    uniform int kr = (R * INV30[p % 30]) % 30;          // k must be = kr (mod 30)
    uniform int k = kmin + ((kr - kmin % 30) + 30) % 30;
    return (p * k - R) / 30;
}

// Base pattern for p: bits at every j = 0 (mod p) over one period of p words, extended to
// L + programCount words. L is a multiple of p that is >= programCount, so advancing the
// phase by programCount needs one conditional subtract (a while loop there compiles to a
// hardware divide).
// tab[t] receives the word whose bit t is set: the 64 multiples of p in one period land on
// 64 distinct bit positions (p odd), so it gives the starting phase for any bit offset t.
static inline uniform int build_pattern(uniform uint64 * uniform pat, uniform int16 * uniform tab, uniform int p) {
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

// OR one pattern into words [b>>6, wend), starting at phase r. First word masked.
// Returns the phase of word wend.
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

static uniform uint64 zero_pat[64];   // padding entry for short groups

// Patterns for a group of up to G primes, built once and shared by all 8 planes.
struct Group {
    uniform int n;
    uniform int p[G], L[G];
    uniform int16 tab[G][64];
    const uniform uint64 * uniform pp[G];
    uniform uint64 buf[G][MAXPAT + 64];
};

static inline void build_group(uniform Group * uniform g, const uniform int * uniform primes,
                               uniform int n) {
    g->n = n;
    for (uniform int j = 0; j < G; j++) {
        if (j < n) {
            g->p[j] = primes[j];
            g->L[j] = build_pattern(g->buf[j], g->tab[j], primes[j]);
            g->pp[j] = g->buf[j];
        } else { g->p[j] = 1; g->L[j] = programCount; g->pp[j] = zero_pat; }
    }
}

// Fused pass over one plane: all group members OR'd in with a single load and store of
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
            uniform int L = g->L[j];
            uniform int r0 = g->tab[j][b[j] & 63];           // no divides
            r[j] = apply_range(w, g->pp[j], L, r0, b[j], start);   // lead-in, returns phase
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

// Large primes: at most one bit per word. All 8 planes advance in one loop, giving 8
// independent read-modify-write streams per iteration and a single loop exit.
static inline void sparse_prime(uniform Sieve * uniform s, uniform int p) {
    uniform int nbits = s->mbits, pw = s->pw;
    uniform uint64 * uniform base = s->bits;
    uniform int i[8];
    uniform int hi = 0;
    for (uniform int pl = 0; pl < 8; pl++) {
        uniform int sb = start_bit(p, RES[pl], p);
        hi = max(hi, sb);
        i[pl] = sb + pl * pw * 64;                     // bit index within the whole buffer
    }
    // rounds in which all 8 streams are still inside their plane
    uniform int fullrounds = (hi < nbits) ? (nbits - 1 - hi) / p + 1 : 0;
    for (uniform int k = 0; k < fullrounds; k++) {
        for (uniform int pl = 0; pl < 8; pl++) {
            base[i[pl] >> 6] |= ((uniform uint64)1) << (i[pl] & 63);
            i[pl] += p;
        }
    }
    for (uniform int pl = 0; pl < 8; pl++) {
        uniform int end = pl * pw * 64 + nbits;
        for (uniform int x = i[pl]; x < end; x += p) base[x >> 6] |= ((uniform uint64)1) << (x & 63);
    }
}

// Apply a group of dense primes (multiples from p*p on) to all 8 planes.
static inline void dense_primes(uniform Sieve * uniform s, const uniform int * uniform primes,
                                uniform int n) {
    uniform Group g;
    build_group(&g, primes, n);
    uniform int b[G];
    for (uniform int pl = 0; pl < 8; pl++) {
        for (uniform int j = 0; j < n; j++) b[j] = start_bit(primes[j], RES[pl], primes[j]);
        apply_group(s->bits + pl * s->pw, s->nw, &g, b);
    }
}

static inline uniform bool is_composite(uniform Sieve * uniform s, uniform int n) {
    uniform int m = n / 30;
    const uniform uint64 * uniform w = s->bits + PLANE[n % 30] * s->pw;
    return ((w[m >> 6] >> (m & 63)) & 1) != 0;
}

static void run_sieve(uniform Sieve * uniform s) {
    uniform int nw = s->nw, pw = s->pw, mbits = s->mbits;

    // Phase 1: wheel tile per plane. 7 and 11 (marked from the primes themselves, so the
    // pattern is exactly periodic) repeat every 77 words: build one period, copy it along.
    uniform int t = min(77, nw);
    uniform int tp[2] = {7, 11};
    uniform Group g;
    build_group(&g, tp, 2);
    for (uniform int pl = 0; pl < 8; pl++) {
        uniform uint64 * uniform w = s->bits + pl * pw;
        foreach (k = 0 ... t) w[k] = 0;
        uniform int tb[2];
        tb[0] = start_bit(7, RES[pl], 1);
        tb[1] = start_bit(11, RES[pl], 1);
        apply_group(w, t, &g, tb);
        for (uniform int base = t; base < nw; base += t) {
            uniform int n = min(t, nw - base);
            foreach (k = 0 ... n) w[base + k] = w[k];
        }
    }
    s->bits[0]      = (s->bits[0] | 1) ;              // 1 is not prime (plane 1, bit 0)
    s->bits[1 * pw] &= ~((uniform uint64)1);          // 7 is prime
    s->bits[2 * pw] &= ~((uniform uint64)1);          // 11 is prime

    // Phase 2: 13 alone; afterwards every bit below 17*17 is final.
    uniform int thirteen[1] = {13};
    dense_primes(s, thirteen, 1);

    // Phase 3: dense primes in fused groups, then sparse primes. A candidate is read only
    // once every prime <= its square root is applied: c < g0*g0 for the smallest pending g0.
    uniform int q = (uniform int)sqrt((uniform float)LIMIT);
    uniform int dm = dense_max;
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

// Count primes: zero bits for n <= LIMIT, plus 2, 3 and 5.
static uniform int count_primes(uniform Sieve * uniform s) {
    uniform int c = 3;
    for (uniform int pl = 0; pl < 8; pl++) {
        const uniform uint64 * uniform w = s->bits + pl * s->pw;
        uniform int mmax = (uniform int)((LIMIT - RES[pl]) / 30);   // last valid bit
        for (uniform int k = 0; k < s->nw; k++) {
            uniform uint64 x = ~w[k];
            uniform int lo = k << 6;
            if (lo + 63 > mmax) {
                if (lo > mmax) x = 0;
                else x &= ~((uniform uint64)0) >> (63 - (mmax - lo));
            }
            c += popcnt(x);
        }
    }
    return c;
}

struct Job { uniform double deadline; uniform int64 passes; uniform int ok; };

export void * uniform worker(void * uniform arg) {
    unmasked {
        uniform Job * uniform job = (uniform Job * uniform)arg;
        uniform int64 passes = 0;
        uniform int okay = 1;
        while (now() < job->deadline) {
            uniform Sieve s;
            s.mbits = (uniform int)(LIMIT / 30) + 1;
            s.nw = (s.mbits + 63) >> 6;
            s.pw = (s.nw + 7) & ~7;
            s.bits = (uniform uint64 * uniform)aligned_alloc(64, 8 * s.pw * 8);
            run_sieve(&s);
            if (passes == 0) okay = (count_primes(&s) == 78498);
            free(s.bits);
            passes++;
        }
        job->passes = passes;
        job->ok = okay;
    }
    return NULL;
}

export uniform int main() {
    uniform int8 name[10] = {68,69,78,83,69,95,77,65,88,0};   // "DENSE_MAX"
    int8 * uniform e = getenv(name);
    if (e != NULL) dense_max = min(atoi(e), MAXPAT);
    uniform int nthreads = get_nprocs();
    uniform Job jobs[512];
    uniform int64 tids[512];

    uniform double start = now();
    jobs[0].deadline = start + 5.0;
    worker(&jobs[0]);
    uniform double t1 = now() - start;
    if (!jobs[0].ok) print("ERROR: wrong prime count\n");
    print("cauldnz-ispc;%;%;1;algorithm=wheel,faithful=no,bits=1\n", jobs[0].passes, t1);

    start = now();
    for (uniform int t = 0; t < nthreads; t++) {
        jobs[t].deadline = start + 5.0;
        pthread_create(&tids[t], NULL, (void * uniform)worker, &jobs[t]);
    }
    uniform int64 total = 0;
    uniform int allok = 1;
    for (uniform int t = 0; t < nthreads; t++) {
        pthread_join(tids[t], NULL);
        total += jobs[t].passes; allok = allok & jobs[t].ok;
    }
    uniform double t2 = now() - start;
    if (!allok) print("ERROR: wrong prime count\n");
    print("cauldnz-ispc;%;%;%;algorithm=wheel,faithful=no,bits=1\n", total, t2, nthreads);
    return 0;
}
