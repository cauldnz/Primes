// Prime sieve drag race, pure ISPC. 1 bit per odd number (bit i <-> 2i+1), set bit = composite.
// Everything is recomputed for every pass; nothing is carried between iterations.

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
static const uniform int TILE = 3 * 5 * 7 * 11;   // words: period of the 3,5,7,11 pattern
static const uniform int MAXPAT = 1024;

static uniform int dense_max = 512;   // primes below this are applied as word patterns

static inline uniform double now() {
    uniform timespec ts;
    clock_gettime(1, &ts);
    return (uniform double)ts.tv_sec + 1e-9 * (uniform double)ts.tv_nsec;
}

// Build one period of the multiples-of-p bit pattern, relative to word w0 = b>>6.
// Period L is a multiple of p that is >= programCount, so advancing the phase by
// programCount needs at most one conditional subtract (a loop here compiles to a divide).
// pat gets L + programCount words so a vector load at any phase < L stays in bounds.
static inline uniform int build_pattern(uniform uint64 * uniform pat, uniform int p, uniform int b) {
    uniform int off = b & 63;
    uniform int L = p;
    while (L < programCount) L += p;
    foreach (k = 0 ... p) pat[k] = 0;
    for (uniform int j = off % p; j < (p << 6); j += p)
        pat[j >> 6] |= ((uniform uint64)1) << (j & 63);
    for (uniform int k = p; k < L + programCount; k++) pat[k] = pat[k - p];
    return L;
}

// OR a single prime's pattern into words [w0, wend). First word masked so nothing below b.
static inline void apply_range(uniform uint64 * uniform w, const uniform uint64 * uniform pat,
                               uniform int L, uniform int b, uniform int wend) {
    uniform int w0 = b >> 6;
    if (w0 >= wend) return;
    w[w0] |= pat[0] & (~((uniform uint64)0) << (b & 63));
    uniform int r = 1;
    uniform int k = w0 + 1;
    for (; k + programCount <= wend; k += programCount) {
        w[k + programIndex] |= pat[r + programIndex];
        r += programCount;
        r = (r >= L) ? r - L : r;
    }
    if (k + programIndex < wend) w[k + programIndex] |= pat[r + programIndex];
}

static inline void apply_pattern(uniform uint64 * uniform w, uniform int wend,
                                 uniform int p, uniform int b) {
    uniform uint64 pat[MAXPAT + 64];
    uniform int L = build_pattern(pat, p, b);
    apply_range(w, pat, L, b, wend);
}

// Fused pass: G primes OR'd into the sieve with one load/store of each sieve word.
#define G 8
static uniform uint64 zero_pat[64];   // padding "prime" with an empty pattern

static void apply_group(uniform uint64 * uniform w, uniform int nwords,
                        uniform int * uniform primes, uniform int n) {
    uniform uint64 patbuf[G][MAXPAT + 64];
    const uniform uint64 * uniform pp[G];
    uniform int L[G], r[G];
    uniform int start = 0;
    for (uniform int j = 0; j < G; j++) {
        if (j < n) {
            uniform int p = primes[j];
            uniform int b = (p * p) >> 1;
            L[j] = build_pattern(patbuf[j], p, b);
            pp[j] = patbuf[j];
            start = max(start, (b >> 6) + 1);
        } else { L[j] = 16; pp[j] = zero_pat; }
    }
    for (uniform int j = 0; j < n; j++) {          // lead-in before the fused section
        uniform int p = primes[j];
            uniform int b = (p * p) >> 1;
        apply_range(w, pp[j], L[j], b, start);
        r[j] = (start - (b >> 6)) % L[j];
    }
    for (uniform int j = n; j < G; j++) r[j] = 0;
    uniform int k = start;
    for (; k + programCount <= nwords; k += programCount) {
        uint64 v = w[k + programIndex];
        for (uniform int j = 0; j < G; j++) {
            v |= pp[j][r[j] + programIndex];
            uniform int t = r[j] + programCount;
            r[j] = (t >= L[j]) ? t - L[j] : t;
        }
        w[k + programIndex] = v;
    }
    if (k + programIndex < nwords) {
        uint64 v = w[k + programIndex];
        for (uniform int j = 0; j < G; j++) v |= pp[j][r[j] + programIndex];
        w[k + programIndex] = v;
    }
}

// Sparse primes: at most one bit per word, unrolled scalar strided clears.
static inline void apply_sparse(uniform uint64 * uniform w, uniform int nbits,
                                uniform int p, uniform int b) {
    uniform int i = b;
    for (; i + 3 * p < nbits; i += 4 * p) {
        uniform int i1 = i + p, i2 = i + 2 * p, i3 = i + 3 * p;
        w[i  >> 6] |= ((uniform uint64)1) << (i  & 63);
        w[i1 >> 6] |= ((uniform uint64)1) << (i1 & 63);
        w[i2 >> 6] |= ((uniform uint64)1) << (i2 & 63);
        w[i3 >> 6] |= ((uniform uint64)1) << (i3 & 63);
    }
    for (; i < nbits; i += p) w[i >> 6] |= ((uniform uint64)1) << (i & 63);
}

struct Sieve { uniform uint64 * uniform bits; uniform int nbits; uniform int nwords; };

static void run_sieve(uniform Sieve * uniform s) {
    uniform int nbits = s->nbits;
    uniform int nwords = s->nwords;
    uniform uint64 * uniform w = s->bits;

    // Phase 1: wheel tile. Mark 3,5,7,11 (from the primes themselves, so the pattern
    // is exactly periodic) over one period, then copy the period across the sieve.
    uniform int t = min(TILE, nwords);
    foreach (k = 0 ... t) w[k] = 0;
    apply_pattern(w, t, 3, 1);
    apply_pattern(w, t, 5, 2);
    apply_pattern(w, t, 7, 3);
    apply_pattern(w, t, 11, 5);
    for (uniform int base = t; base < nwords; base += t) {
        uniform int n = min(t, nwords - base);
        foreach (k = 0 ... n) w[base + k] = w[k];
    }
    w[0] &= ~((((uniform uint64)1) << 1) | (((uniform uint64)1) << 2) |
              (((uniform uint64)1) << 3) | (((uniform uint64)1) << 5));

    // Phase 2: 13 alone. After it, every bit below 17*17 is final.
    apply_pattern(w, nwords, 13, (13 * 13) >> 1);

    // Phase 3: dense primes in fused groups, then sparse primes as bit clears.
    // A candidate p is only read once every prime <= sqrt(p) has been applied, i.e.
    // p < g0*g0 where g0 is the smallest prime still pending in the group.
    uniform int q = (uniform int)sqrt((uniform float)LIMIT);
    uniform int dm = dense_max;
    uniform int grp[G];
    uniform int n = 0;
    for (uniform int i = 8; 2 * i + 1 <= q; i++) {
        uniform int p = 2 * i + 1;
        if (n > 0 && (p >= dm || p >= grp[0] * grp[0])) { apply_group(w, nwords, grp, n); n = 0; }
        if ((w[i >> 6] >> (i & 63)) & 1) continue;
        if (p < dm) {
            grp[n++] = p;
            if (n == G) { apply_group(w, nwords, grp, n); n = 0; }
        } else {
            apply_sparse(w, nbits, p, (p * p) >> 1);
        }
    }
    if (n > 0) apply_group(w, nwords, grp, n);
    // clear padding bits past the end so they can't be read as primes
    if (nbits & 63) w[nwords - 1] |= ~((uniform uint64)0) << (nbits & 63);
}

static uniform int count_primes(uniform Sieve * uniform s) {
    uniform int c = 1;  // the prime 2
    for (uniform int k = 0; k < s->nwords; k++) c += popcnt(~s->bits[k]);
    return c - 1;       // bit 0 is the number 1
}

struct Job { uniform double deadline; uniform int64 passes; uniform int ok; };

export void * uniform worker(void * uniform arg) {
    unmasked {
        uniform Job * uniform job = (uniform Job * uniform)arg;
        uniform int64 passes = 0;
        uniform int okay = 1;
        while (now() < job->deadline) {
            uniform Sieve s;
            s.nbits = (uniform int)(LIMIT / 2);
            s.nwords = (s.nbits + 63) >> 6;
            s.bits = (uniform uint64 * uniform)aligned_alloc(64, ((s.nwords * 8 + 63) / 64) * 64);
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
    uniform int8 name[10] = {68,69,78,83,69,95,77,65,88,0};  // "DENSE_MAX"
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
