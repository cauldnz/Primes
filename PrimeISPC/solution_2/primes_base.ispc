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
// On x86, after the dense phase the sparse factors clear the sieve block by block, as
// rogiervandam's base entry (PrimeC/solution_5, shakeSieve) does: for each block of the bit
// array (16 KB by default, so it stays in L1), every sparse factor clears its multiples inside
// the block, stepping 2 x factor, and carries its next position on to the following block.
// Each composite is still cleared by its own single-bit OR; only the nesting of the loops
// changes. NEON builds keep the unblocked sparse phase.
//
// Sweep direction alternates by factor: the first factor (3) sweeps the sieve from the low end
// up, the next from the high end down, and so on. A descending sweep visits the same
// composites as an ascending one, each with its own single-bit OR and stepping 2 x factor,
// from the last multiple below the sieve end down to the chunk holding factor squared. The
// end of one sweep is the start of the next, so that part of the sieve is still in L1. On x86
// the sparse factors go on alternating inside each block: one sweeps the block up, the next
// down.
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

// P itself is prime: undo the OR the dense routines give it when P*P falls in chunk 0.
static inline void restore_factor(uniform uint64 * uniform w, uniform int nwords, const uniform int P) {
    const uniform int f = P / 2;
    if ((f >> 6) < nwords) w[f >> 6] &= ~(((uniform uint64)1) << (f & 63));
}

// Descending form of clear_dense_from, without the restore: the same composites in words
// c0..nwords-1, visited top down. The partial last chunk goes first, then the whole chunks
// from the highest down to the one starting at c0.
static inline void clear_dense_down_to(uniform uint64 * uniform w, uniform int nwords,
                                       const uniform int P, uniform int c0) {
    uniform int c = c0 + (nwords - c0) / P * P;                    // start of the partial chunk
    for (uniform int j = 63; j >= 0; j--) {
        const uniform int t = P / 2 + j * P;
        if (c + (t >> 6) < nwords) w[c + (t >> 6)] |= ((uniform uint64)1) << (t & 63);
    }
    while (c > c0) {
        c -= P;
        #pragma unroll
        for (uniform int j = 63; j >= 0; j--) {
            const uniform int t = P / 2 + j * P;
            w[c + (t >> 6)] |= ((uniform uint64)1) << (t & 63);    // one composite
        }
    }
}

static inline void clear_dense_down(uniform uint64 * uniform w, uniform int nwords, const uniform int P) {
    clear_dense_down_to(w, nwords, P, ((P * P / 2) / 64 / P) * P);
    restore_factor(w, nwords, P);
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

// Descending form of clear_dense_vec (never the INIT pass): the scalar words after the last
// whole block go first, then the blocks from the highest down, each one vector at a time from
// its top vector down.
static inline void clear_dense_vec_down(uniform uint64 * uniform w, uniform int nwords,
                                        const uniform int P) {
    const uniform int B = programCount * P;                        // words per block
    const uniform int c0 = ((P * P / 2) / 64 / P) * P;
    uniform int c = c0 + (nwords - c0) / B * B;                    // end of the last whole block
    clear_dense_down_to(w, nwords, P, c);
    while (c > c0) {
        c -= B;
        #pragma unroll
        for (uniform int kb = B - programCount; kb >= 0; kb -= programCount) {
            const int k = kb + programIndex;                        // word of the block
            uint64 x = w[c + k];
            const uniform int n0 = (64 * kb - P / 2) / P;          // first composite near these words
            #pragma unroll
            for (uniform int i = 0; i < 64 * programCount / P + 2; i++) {
                const uniform int t = P / 2 + (n0 + i) * P;
                x |= ((t >> 6) == k) ? ((uniform uint64)1) << (t & 63) : 0;   // one composite
            }
            w[c + k] = x;
        }
    }
    restore_factor(w, nwords, P);
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

// Descending form of clear_dense_neon: the words after the last whole run go first, top down;
// then the runs from the highest down, each with its scalar words first and then its vectors
// from the top one down.
static inline void clear_dense_neon_down(uniform uint64 * uniform w, uniform int nwords,
                                         const uniform int P) {
    const uniform int U = (P < 16) ? programCount : 1;             // periods per run
    const uniform int B = U * P;                                   // words per run
    const uniform int NV = B / programCount;                       // whole vectors per run
    const uniform int c = ((P * P / 2) / 64 / P) * P;
    uniform int n = (nwords - c) / B;
    clear_dense_down_to(w, nwords, P, c + n * B);                  // the rest, top down
    uniform uint64 * uniform q = w + c + n * B;
    for (; n > 0; n--) {
        q -= B;
        #pragma unroll
        for (uniform int j = 64 * U - 1; j >= 0; j--) {             // words after the vectors
            const uniform int t = P / 2 + j * P;
            if ((t >> 6) >= NV * programCount)
                q[t >> 6] |= ((uniform uint64)1) << (t & 63);       // one composite
        }
        #pragma unroll
        for (uniform int v = NV - 1; v >= 0; v--) {
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
    }
    restore_factor(w, nwords, P);
}
#endif

// The sparse factors clear the sieve block by block on x86 only. On NEON each one sweeps the
// whole sieve, as the dense factors do: blocking cost 2% on a Neoverse N2.
#if defined(ISPC_TARGET_NEON)
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

// Descending form of clear_sparse_e: the partial last chunk first, its composites from the
// highest down, then the whole chunks from the highest down to the one holding p*p.
static inline void clear_sparse_e_down(uniform uint8 * uniform bytes, uniform int nbytes,
                                       uniform int p, const uniform int E) {
    uniform int o0 = (p / 2) >> 3,           o1 = (p / 2 + p) >> 3;
    uniform int o2 = (p / 2 + 2 * p) >> 3,   o3 = (p / 2 + 3 * p) >> 3;
    uniform int o4 = (p / 2 + 4 * p) >> 3,   o5 = (p / 2 + 5 * p) >> 3;
    uniform int o6 = (p / 2 + 6 * p) >> 3,   o7 = (p / 2 + 7 * p) >> 3;
    const uniform uint8 m0 = 1 << ((E / 2) & 7),         m1 = 1 << ((E / 2 + E) & 7);
    const uniform uint8 m2 = 1 << ((E / 2 + 2 * E) & 7), m3 = 1 << ((E / 2 + 3 * E) & 7);
    const uniform uint8 m4 = 1 << ((E / 2 + 4 * E) & 7), m5 = 1 << ((E / 2 + 5 * E) & 7);
    const uniform uint8 m6 = 1 << ((E / 2 + 6 * E) & 7), m7 = 1 << ((E / 2 + 7 * E) & 7);
    const uniform int c0 = ((p * p / 2) / 8 / p) * p;               // chunk holding p*p
    uniform uint8 * uniform first = bytes + c0;
    uniform uint8 * uniform q = first + (nbytes - c0) / p * p;      // the partial last chunk
    uniform uint8 * uniform end = bytes + nbytes;
    if (q + o7 < end) q[o7] |= m7;
    if (q + o6 < end) q[o6] |= m6;
    if (q + o5 < end) q[o5] |= m5;
    if (q + o4 < end) q[o4] |= m4;
    if (q + o3 < end) q[o3] |= m3;
    if (q + o2 < end) q[o2] |= m2;
    if (q + o1 < end) q[o1] |= m1;
    if (q + o0 < end) q[o0] |= m0;
    while (q > first) {                                             // one composite each
        q -= p;
        q[o7] |= m7; q[o6] |= m6; q[o5] |= m5; q[o4] |= m4;
        q[o3] |= m3; q[o2] |= m2; q[o1] |= m1; q[o0] |= m0;
    }
}

#define SPARSE(E) case E: if (down) clear_sparse_e_down(b, nbytes, p, E); \
                          else clear_sparse_e(b, nbytes, p, E); break;

static void clear_sparse(uniform Sieve * uniform s, uniform int p, uniform bool down) {
    uniform uint8 * uniform b = (uniform uint8 * uniform)s->bits;
    uniform int nbytes = s->nwords * 8;
    switch (p & 15) {
        SPARSE(1) SPARSE(3) SPARSE(5) SPARSE(7) SPARSE(9) SPARSE(11) SPARSE(13)
        default: if (down) clear_sparse_e_down(b, nbytes, p, 15);
                 else clear_sparse_e(b, nbytes, p, 15); break;
    }
}
#else
// Sparse clearing over bytes for an odd factor p > 16, one block at a time. Chunks of p bytes
// start at byte multiples of p; in each, the 8 multiples sit at bit offsets t_j = p/2 + j*p
// (j = 0..7), at byte offsets o_j < p in ascending order. Their bit-in-byte positions depend
// only on p mod 16 (E), so the masks are constants. A factor's state is the chunk it has
// reached and the first of that chunk's 8 multiples it has not cleared yet.
struct Sparse {
    uniform int p;        // the factor
    uniform int c;        // byte offset of the current chunk (a multiple of p)
    uniform int j;        // next multiple in that chunk, 0..7
};

static inline void sparse_init(uniform Sparse * uniform f, uniform int p) {
    f->p = p;
    f->c = ((p * p / 2) / 8 / p) * p;     // the chunk holding p*p; smaller multiples are composite too
    f->j = 0;
}

// Clear f's multiples in the bytes below end_off, starting where f stopped.
static inline void clear_sparse_e(uniform uint8 * uniform bytes, uniform Sparse * uniform f,
                                  uniform int end_off, const uniform int E) {
    const uniform int p = f->p;
    uniform int o0 = (p / 2) >> 3,           o1 = (p / 2 + p) >> 3;
    uniform int o2 = (p / 2 + 2 * p) >> 3,   o3 = (p / 2 + 3 * p) >> 3;
    uniform int o4 = (p / 2 + 4 * p) >> 3,   o5 = (p / 2 + 5 * p) >> 3;
    uniform int o6 = (p / 2 + 6 * p) >> 3,   o7 = (p / 2 + 7 * p) >> 3;
    const uniform uint8 m0 = 1 << ((E / 2) & 7),         m1 = 1 << ((E / 2 + E) & 7);
    const uniform uint8 m2 = 1 << ((E / 2 + 2 * E) & 7), m3 = 1 << ((E / 2 + 3 * E) & 7);
    const uniform uint8 m4 = 1 << ((E / 2 + 4 * E) & 7), m5 = 1 << ((E / 2 + 5 * E) & 7);
    const uniform uint8 m6 = 1 << ((E / 2 + 6 * E) & 7), m7 = 1 << ((E / 2 + 7 * E) & 7);
    uniform uint8 * uniform q = bytes + f->c;
    uniform uint8 * uniform end = bytes + end_off;
    // Head: the rest of a chunk that the previous block's edge cut short.
    uniform int j = f->j;
    if (j != 0) {
        uniform int o[8] = {o0, o1, o2, o3, o4, o5, o6, o7};
        uniform uint8 m[8] = {m0, m1, m2, m3, m4, m5, m6, m7};
        for (; j < 8; j++) {
            if (q + o[j] >= end) { f->j = j; return; }
            q[o[j]] |= m[j];                                        // one composite
        }
        q += p;
    }
    // Whole chunks inside the block. Walk a pointer over the chunks: each OR is then one
    // instruction with a register offset. Indexing with a 32-bit chunk offset cost a sign
    // extension and an add per composite.
    for (; q + p <= end; q += p) {                                  // one composite each
        q[o0] |= m0; q[o1] |= m1; q[o2] |= m2; q[o3] |= m3;
        q[o4] |= m4; q[o5] |= m5; q[o6] |= m6; q[o7] |= m7;
    }
    // Tail: the part of the next chunk that lies below end. Record where it stopped.
    f->c = (uniform int)(q - bytes);
    f->j = 0;
    if (q + o0 < end) q[o0] |= m0; else return;
    f->j = 1; if (q + o1 < end) q[o1] |= m1; else return;
    f->j = 2; if (q + o2 < end) q[o2] |= m2; else return;
    f->j = 3; if (q + o3 < end) q[o3] |= m3; else return;
    f->j = 4; if (q + o4 < end) q[o4] |= m4; else return;
    f->j = 5; if (q + o5 < end) q[o5] |= m5; else return;
    f->j = 6; if (q + o6 < end) q[o6] |= m6; else return;
    f->j = 7; if (q + o7 < end) q[o7] |= m7; else return;
    f->c += p;                                                      // the whole chunk fitted
    f->j = 0;
}

// Descending form of clear_sparse_e: the same multiples of f, those from where f stopped up to
// end_off, visited top down. f's state moves on to the first multiple at or above end_off
// first; then the chunk holding end_off goes, its multiples below end_off from the highest
// down, then the whole chunks from the highest down, then the chunk where f stopped, down to
// the multiple it stopped at.
static inline void clear_sparse_e_down(uniform uint8 * uniform bytes, uniform Sparse * uniform f,
                                       uniform int end_off, const uniform int E) {
    const uniform int p = f->p;
    uniform int o0 = (p / 2) >> 3,           o1 = (p / 2 + p) >> 3;
    uniform int o2 = (p / 2 + 2 * p) >> 3,   o3 = (p / 2 + 3 * p) >> 3;
    uniform int o4 = (p / 2 + 4 * p) >> 3,   o5 = (p / 2 + 5 * p) >> 3;
    uniform int o6 = (p / 2 + 6 * p) >> 3,   o7 = (p / 2 + 7 * p) >> 3;
    const uniform uint8 m0 = 1 << ((E / 2) & 7),         m1 = 1 << ((E / 2 + E) & 7);
    const uniform uint8 m2 = 1 << ((E / 2 + 2 * E) & 7), m3 = 1 << ((E / 2 + 3 * E) & 7);
    const uniform uint8 m4 = 1 << ((E / 2 + 4 * E) & 7), m5 = 1 << ((E / 2 + 5 * E) & 7);
    const uniform uint8 m6 = 1 << ((E / 2 + 6 * E) & 7), m7 = 1 << ((E / 2 + 7 * E) & 7);
    if (f->c >= end_off) return;                                    // nothing below end_off
    uniform int o[8] = {o0, o1, o2, o3, o4, o5, o6, o7};
    uniform uint8 m[8] = {m0, m1, m2, m3, m4, m5, m6, m7};
    uniform uint8 * uniform first = bytes + f->c;
    const uniform int j0 = f->j;
    uniform uint8 * uniform q = first + (end_off - f->c) / p * p;   // q <= end < q + p
    uniform uint8 * uniform end = bytes + end_off;
    uniform int jn = (q == first) ? j0 : 0;                         // first multiple at or above end
    while (jn < 8 && q + o[jn] < end) jn++;
    if (jn == 8) { f->c = (uniform int)(q - bytes) + p; f->j = 0; }
    else         { f->c = (uniform int)(q - bytes);     f->j = jn; }
    const uniform int lo = (q == first) ? j0 : 0;
    for (uniform int j = jn - 1; j >= lo; j--) q[o[j]] |= m[j];    // one composite each
    if (q == first) return;
    q -= p;
    while (q > first) {                                             // one composite each
        q[o7] |= m7; q[o6] |= m6; q[o5] |= m5; q[o4] |= m4;
        q[o3] |= m3; q[o2] |= m2; q[o1] |= m1; q[o0] |= m0;
        q -= p;
    }
    for (uniform int j = 7; j >= j0; j--) q[o[j]] |= m[j];         // where f stopped
}

#define SPARSE(E) case E: if (down) clear_sparse_e_down(b, f, end_off, E); \
                          else clear_sparse_e(b, f, end_off, E); break;

// Clear sparse factor f's multiples up to byte end_off of the sieve, from where it stopped,
// from the low end up or from the high end down.
static void clear_sparse(uniform Sieve * uniform s, uniform Sparse * uniform f,
                         uniform int end_off, uniform bool down) {
    uniform uint8 * uniform b = (uniform uint8 * uniform)s->bits;
    switch (f->p & 15) {
        SPARSE(1) SPARSE(3) SPARSE(5) SPARSE(7) SPARSE(9) SPARSE(11) SPARSE(13)
        default: if (down) clear_sparse_e_down(b, f, end_off, 15);
                 else clear_sparse_e(b, f, end_off, 15); break;
    }
}
#endif

#if defined(ISPC_TARGET_NEON)
#define D(P) case P: if (down) clear_dense_neon_down(s->bits, s->nwords, P); \
                     else clear_dense_neon(s->bits, s->nwords, P); break;
#else
// Factor 3 never goes down (see run_sieve), so its descending form isn't built: its ascending
// pass is the one that initialises the sieve.
#define D(P) case P: if (P < VEC_LIMIT) { \
                         if (down && P != 3) clear_dense_vec_down(s->bits, s->nwords, P); \
                         else clear_dense_vec(s->bits, s->nwords, P, P == 3); \
                     } else if (down) clear_dense_down(s->bits, s->nwords, P); \
                     else clear_dense(s->bits, s->nwords, P); break;
#endif

// Clear all odd multiples of factor p, from the low end up or from the high end down. On x86
// p is always dense; the sparse factors go through the blocked loop in run_sieve.
static void clear_factor(uniform Sieve * uniform s, uniform int p, uniform bool down) {
    // clear_factor isn't inlined, so ISPC would compile it for an unknown execution mask and
    // mask every vector load and store in the dense code. Callers run with all lanes on.
    unmasked {
#if defined(ISPC_TARGET_NEON)
        if (p >= DENSE_LIMIT) { clear_sparse(s, p, down); return; }
#endif
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

#if !defined(ISPC_TARGET_NEON)
// Sparse block size in bytes: 16 KB unless PRIMES_BLOCK_KB says otherwise. main() reads the
// variable once, before any sieve runs.
#define BLOCK_KB 16
static uniform int block_bytes = BLOCK_KB * 1024;

// Sizes are below 2^32 (nbits is an int), so sqrt(size) < 65536, below which lie 6542 primes.
#define MAX_SPARSE 6560
#endif

// The base algorithm: find the next prime, clear its multiples, repeat up to sqrt(size).
// Dense factors clear the whole sieve one after another. On x86 the sparse factors clear it
// block by block (see the header); on NEON they go on as the dense ones do.
//
// The sparse factors are the ones the unblocked loop finds, collected as the outer loop runs
// over the first block. The scan for the next prime reads bits up to index q/2 (factor q) and
// stops there or at the first prime before it; any bit it reads past q/2 only ends the loop.
// The first block is made at least q/2 bits long, and each factor found clears its multiples
// in the first block before the scan moves on. So when the scan reaches a candidate, every
// smaller factor, dense or sparse, has already cleared every bit the scan can act on, as in
// the unblocked loop: it sees the same bits and finds the same factors. The later blocks hold
// no candidates, so the list is complete before they start.
static void run_sieve(uniform Sieve * uniform s) {
    uniform int q = (uniform int)sqrt((uniform double)s->size);
    while ((uniform int64)(q + 1) * (q + 1) <= s->size) q++;
    while ((uniform int64)q * q > s->size) q--;
    uniform int factor = 3;
    // Direction alternates by factor. The first factor, 3, always sweeps up: on x86 its pass
    // writes every word of the sieve (sieve_create clears only word 0), so it has to come
    // before any other factor reads a word, whatever the direction of the ones after it.
    uniform bool down = false;
    while (factor <= q) {
        uniform int i = factor >> 1;
        while (i < s->nbits && is_composite_index(s, i)) i++;     // next prime
        factor = 2 * i + 1;
        if (factor > q) break;
#if !defined(ISPC_TARGET_NEON)
        if (factor >= DENSE_LIMIT) break;                           // the sparse factors follow
#endif
        clear_factor(s, factor, down);
        down = !down;
        factor += 2;
    }
#if !defined(ISPC_TARGET_NEON)
    if (factor > q) return;                                         // no sparse factors

    // First block: the outer loop goes on, each sparse factor clearing up to first_end. The
    // sparse factors carry on the alternation: in every block, factor k of the list sweeps
    // down if (k & 1) != down0.
    const uniform bool down0 = down;
    const uniform int nbytes = s->nwords * 8;
    uniform int first_end = max(block_bytes, (q >> 1) / 8 + 1);    // holds bits 0..q/2
    first_end = min(first_end, nbytes);
    uniform Sparse fs[MAX_SPARSE];
    uniform int nf = 0;
    while (factor <= q) {                                           // factor is the next prime
        sparse_init(&fs[nf], factor);
        clear_sparse(s, &fs[nf], first_end, ((nf & 1) != 0) != down0);
        nf++;
        uniform int i = (factor + 2) >> 1;
        while (i < s->nbits && is_composite_index(s, i)) i++;     // next prime
        factor = 2 * i + 1;
    }

    // Later blocks: every sparse factor in turn, carrying on from where it stopped.
    for (uniform int start = first_end; start < nbytes; start += block_bytes) {
        const uniform int end = min(start + block_bytes, nbytes);
        for (uniform int k = 0; k < nf; k++)
            clear_sparse(s, &fs[k], end, ((k & 1) != 0) != down0);
    }
#endif
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

export uniform int main() {
#if !defined(ISPC_TARGET_NEON)
    uniform int8 n_block[16] = {80,82,73,77,69,83,95,66,76,79,67,75,95,75,66,0}; // PRIMES_BLOCK_KB
    block_bytes = max(env_int(n_block, BLOCK_KB), 1) * 1024;
#endif
    uniform int8 n_test[12] = {80,82,73,77,69,83,95,84,69,83,84,0};    // PRIMES_TEST
    if (env_int(n_test, 0) != 0) self_test();

    uniform int nthreads = clamp(hardware_threads(), 1, 1024);
    uniform Job jobs[1024];
    uniform int64 tids[1024];

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
