// Prototype: 1-bit, odds-only Eratosthenes sieve in pure ISPC.
// bit i represents the odd number 2*i+1. A set bit means "composite".

struct timespec { int64 tv_sec; int64 tv_nsec; };
extern "C" uniform int clock_gettime(uniform int clk, uniform timespec * uniform ts);
extern "C" void * uniform calloc(uniform int64 n, uniform int64 sz);
extern "C" void free(void * uniform p);
extern "C" uniform int pthread_create(uniform int64 * uniform tid, void * uniform attr,
                                      void * uniform fn, void * uniform arg);
extern "C" uniform int pthread_join(uniform int64 tid, void * uniform * uniform ret);
extern "C" uniform int get_nprocs();

static const uniform int64 LIMIT = 1000000;

static inline uniform double now() {
    uniform timespec ts;
    clock_gettime(1, &ts);
    return (uniform double)ts.tv_sec + 1e-9 * (uniform double)ts.tv_nsec;
}

// Clear multiples of p, starting at bit index b, across the whole sieve.
// Dense primes: one SIMD lane per 64-bit word, each lane builds its own mask.
static inline void clear_dense(uniform uint64 * uniform w, uniform int nwords,
                               uniform int nbits, uniform int p, uniform int b) {
    // The bit pattern of multiples of p repeats every p words (64 is coprime to odd p).
    // Build one period starting at word w0 (scalar, <= 63 words), then tile it with SIMD.
    uniform int w0 = b >> 6;
    uniform uint64 pat[64];
    for (uniform int k = 0; k < p; k++) pat[k] = 0;
    uniform int off = b - (w0 << 6);
    for (uniform int j = off % p; j < (p << 6); j += p) pat[j >> 6] |= ((uniform uint64)1) << (j & 63);
    // first word: only bits at or above p*p
    w[w0] |= pat[0] & (~((uniform uint64)0) << off);
    // lanes walk the period with an incremental residue: no divide in the loop
    uniform int step = programCount % p;
    int r = (1 + programIndex) % p;
    for (uniform int k = w0 + 1; k < nwords; k += programCount) {
        int idx = k + programIndex;
        if (idx < nwords) w[idx] |= pat[r];
        r += step; if (r >= p) r -= p;
    }
}

// Sparse primes: at most a couple of bits per word, plain strided clears.
static inline void clear_sparse(uniform uint64 * uniform w, uniform int nbits,
                                uniform int p, uniform int b) {
    uniform int i = b;
    uniform int p4 = p * 4;
    for (; i + 3 * p < nbits; i += p4) {
        w[i >> 6]           |= ((uniform uint64)1) << (i & 63);
        w[(i + p) >> 6]     |= ((uniform uint64)1) << ((i + p) & 63);
        w[(i + 2*p) >> 6]   |= ((uniform uint64)1) << ((i + 2*p) & 63);
        w[(i + 3*p) >> 6]   |= ((uniform uint64)1) << ((i + 3*p) & 63);
    }
    for (; i < nbits; i += p) w[i >> 6] |= ((uniform uint64)1) << (i & 63);
}

struct Sieve { uniform uint64 * uniform bits; uniform int nbits; uniform int nwords; };

static void run_sieve(uniform Sieve * uniform s) {
    uniform int nbits = s->nbits;
    uniform int nwords = s->nwords;
    uniform uint64 * uniform w = s->bits;
    foreach (k = 0 ... nwords) w[k] = 0;
    uniform int q = (uniform int)sqrt((uniform float)LIMIT);
    for (uniform int i = 1; 2 * i + 1 <= q; i++) {
        if ((w[i >> 6] >> (i & 63)) & 1) continue;
        uniform int p = 2 * i + 1;
        uniform int b = (p * p) >> 1;
        if (p < 64) clear_dense(w, nwords, nbits, p, b);
        else        clear_sparse(w, nbits, p, b);
    }
}

static uniform int count_primes(uniform Sieve * uniform s) {
    uniform int c = 1;  // the prime 2
    for (uniform int i = 1; i < s->nbits; i++)
        if (!((s->bits[i >> 6] >> (i & 63)) & 1)) c++;
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
            s.nbits = (uniform int)(LIMIT / 2);
            s.nwords = (s.nbits + 63) >> 6;
            s.bits = (uniform uint64 * uniform)calloc(s.nwords, 8);
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
    uniform int nthreads = get_nprocs();
    uniform double start = now();
    uniform Job jobs[256];
    uniform int64 tids[256];
    // single-threaded run
    jobs[0].deadline = start + 5.0;
    worker(&jobs[0]);
    uniform double t1 = now() - start;
    print("cauldnz-ispc-st;%;%;1;algorithm=other,faithful=no,bits=1 ok=%\n",
          jobs[0].passes, t1, jobs[0].ok);
    // multi-threaded run
    start = now();
    for (uniform int t = 0; t < nthreads; t++) {
        jobs[t].deadline = start + 5.0;
        pthread_create(&tids[t], NULL, (void * uniform)worker, &jobs[t]);
    }
    uniform int64 total = 0;
    for (uniform int t = 0; t < nthreads; t++) { pthread_join(tids[t], NULL); total += jobs[t].passes; }
    uniform double t2 = now() - start;
    print("cauldnz-ispc-mt;%;%;%;algorithm=other,faithful=no,bits=1\n", total, t2, nthreads);
    return 0;
}
