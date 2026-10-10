//! Prime sieve drag race: a Rust base-algorithm solution by cauldnz.
//!
//! The base algorithm: an outer loop finds the next prime, then clears every one of its odd
//! multiples individually. Bit i of the sieve stands for the odd number 2i + 1; a set bit means
//! composite. Every composite gets its own single-bit OR; no operation in the source sets more
//! than one composite.
//!
//! This is the design of the author's ISPC base entry (PrimeISPC/solution_2), which in turn
//! follows mike-barber's Rust (PrimeRust/solution_1) and GordonBGood's Chapel solutions:
//!
//! * Dense (factor below 128): the odd multiples of p repeat with a period of p 64-bit words.
//!   The resetter is instantiated for every odd factor below 128 with the factor as a const
//!   generic, works on runs of four periods (4p words, p vectors of four words) and ORs one
//!   compile-time mask vector into each `[u64; 4]`.
//! * Sparse (larger factors): eight multiples repeat every p bytes, each at a fixed bit. The
//!   byte offsets are computed per factor; the eight masks are const generics chosen by p mod 16.

use std::alloc::{self, Layout};
use std::env;
use std::process::ExitCode;
use std::ptr::NonNull;
use std::thread;
use std::time::{Duration, Instant};

const SIEVE_SIZE: u64 = 1_000_000;
const EXPECTED: usize = 78_498;
const RUN_TIME: Duration = Duration::from_secs(5);
const LABEL: &str = "cauldnz-rust-base";
const TAGS: &str = "algorithm=base,faithful=yes,bits=1";

/// Factors below this use the dense resetter, larger ones the sparse one.
const DENSE_LIMIT: usize = 128;

/// All of one sieve's state. A new one is created, and its buffer allocated, for every pass.
struct Sieve {
    size: u64,
    /// One bit per odd number 1, 3, 5, ... up to `size`.
    nbits: usize,
    nwords: usize,
    words: NonNull<u64>,
    layout: Layout,
}

impl Sieve {
    fn new(size: u64) -> Self {
        let nbits = size.div_ceil(2) as usize;
        let nwords = nbits.div_ceil(64);
        // 64-byte aligned, rounded up to whole cache lines, never empty.
        let bytes = (nwords * 8).div_ceil(64).max(1) * 64;
        let layout = Layout::from_size_align(bytes, 64).expect("sieve layout");
        // SAFETY: the layout has a nonzero size.
        let raw = unsafe { alloc::alloc(layout) } as *mut u64;
        let words = NonNull::new(raw).unwrap_or_else(|| alloc::handle_alloc_error(layout));
        // Only word 0 is cleared here, so the scan can read the bit for 3. The first factor the
        // scan finds is always 3, and its dense pass writes every word without reading it, so
        // the rest of the buffer is initialised there. No word is read before it is written.
        // SAFETY: the buffer holds at least one word.
        unsafe { words.as_ptr().write(0) };
        Sieve { size, nbits, nwords, words, layout }
    }

    #[inline(always)]
    fn is_composite(&self, i: usize) -> bool {
        debug_assert!(i < self.nbits);
        // SAFETY: i < nbits, so the word is inside the buffer, and the scan only reaches words
        // the pass for 3 has written (or word 0, written in `new`).
        unsafe { (*self.words.as_ptr().add(i >> 6) >> (i & 63)) & 1 != 0 }
    }

    /// The base algorithm: find the next prime, clear its multiples, repeat up to sqrt(size).
    fn run(&mut self) {
        let mut q = (self.size as f64).sqrt() as u64;
        while (q + 1) * (q + 1) <= self.size {
            q += 1;
        }
        while q * q > self.size {
            q -= 1;
        }
        let mut factor = 3u64;
        while factor <= q {
            let mut i = (factor >> 1) as usize;
            while i < self.nbits && self.is_composite(i) {
                i += 1; // next prime
            }
            factor = 2 * i as u64 + 1;
            if factor > q {
                break;
            }
            self.clear_factor(factor as usize);
            factor += 2;
        }
    }

    /// Clear all odd multiples of `p`, from p², with one single-bit OR per composite.
    fn clear_factor(&mut self, p: usize) {
        let w = self.words.as_ptr();
        let n = self.nwords;
        // SAFETY (all arms): p is odd, p >= 3 and p² <= size, which is what the resetters need.
        unsafe {
            if p >= DENSE_LIMIT {
                let b = w as *mut u8;
                match p & 15 {
                    1 => clear_sparse::<1>(b, n * 8, p),
                    3 => clear_sparse::<3>(b, n * 8, p),
                    5 => clear_sparse::<5>(b, n * 8, p),
                    7 => clear_sparse::<7>(b, n * 8, p),
                    9 => clear_sparse::<9>(b, n * 8, p),
                    11 => clear_sparse::<11>(b, n * 8, p),
                    13 => clear_sparse::<13>(b, n * 8, p),
                    _ => clear_sparse::<15>(b, n * 8, p),
                }
                return;
            }
            macro_rules! dense {
                ($($p:literal)*) => {
                    match p {
                        // 3 is always the first factor: its pass initialises the buffer.
                        3 => clear_dense::<3, true>(w, n),
                        $($p => clear_dense::<$p, false>(w, n),)*
                        _ => unreachable!("even factor {p}"),
                    }
                };
            }
            dense!(5 7 9 11 13 15 17 19 21 23 25 27 29 31 33 35 37 39 41 43 45 47 49 51 53 55 57
                   59 61 63 65 67 69 71 73 75 77 79 81 83 85 87 89 91 93 95 97 99 101 103 105
                   107 109 111 113 115 117 119 121 123 125 127);
        }
    }

    /// Primes up to and including `size`: unmarked odd numbers from 3, plus 2.
    fn count_primes(&self) -> usize {
        if self.size < 2 {
            return 0;
        }
        1 + (1..self.nbits).filter(|&i| !self.is_composite(i)).count()
    }
}

impl Drop for Sieve {
    fn drop(&mut self) {
        // SAFETY: allocated in `new` with this layout.
        unsafe { alloc::dealloc(self.words.as_ptr() as *mut u8, self.layout) };
    }
}

/// Bit i is the odd number 2i + 1, so the multiple p(2j + 1) of p sits at bit p/2 + jp. Four
/// periods (4p words) hold 256 multiples at fixed positions. `MASKS[v]` sets, for vector v of
/// a run (words 4v to 4v + 3), each of those multiples with its own single-bit OR; it is
/// evaluated at compile time, so the run's ORs become constants.
struct Dense<const P: usize>;

impl<const P: usize> Dense<P> {
    const MASKS: [[u64; 4]; P] = {
        let mut m = [[0u64; 4]; P];
        let mut j = 0;
        while j < 256 {
            let t = P / 2 + j * P; // bit of the multiple P(2j + 1)
            m[(t >> 6) / 4][(t >> 6) % 4] |= 1u64 << (t & 63); // one composite
            j += 1;
        }
        m
    };
}

/// Dense clearing for a compile-time odd factor P. Periods of P words start at word multiples
/// of P; clearing starts at the period holding P². The smaller multiples in that period are
/// composite too, except P itself, which is restored at the end. The loop walks runs of four
/// periods, one `[u64; 4]` vector at a time; the last, partial run takes as many whole vectors
/// as fit, then one to three single words, with the same masks. With `INIT` (the first factor)
/// every word is stored without being loaded, which initialises the buffer.
///
/// # Safety
/// `w` points to at least `nwords` words, all initialised unless `INIT`; P² <= the sieve size.
#[inline(never)]
unsafe fn clear_dense<const P: usize, const INIT: bool>(w: *mut u64, nwords: usize) {
    #[inline(always)]
    unsafe fn or4<const P: usize, const INIT: bool>(a: *mut u64, v: usize) {
        let a = a as *mut [u64; 4];
        let mut x = if INIT { [0; 4] } else { a.read_unaligned() };
        let m = Dense::<P>::MASKS[v];
        for l in 0..4 {
            x[l] |= m[l];
        }
        a.write_unaligned(x);
    }

    let c0 = (P * P / 2) / 64 / P * P;
    debug_assert!(c0 < nwords);
    let runs = (nwords - c0) / (4 * P);
    let mut q = w.add(c0);
    // SAFETY: each run covers 4P words that end at or before nwords.
    for _ in 0..runs {
        for v in 0..P {
            or4::<P, INIT>(q.add(4 * v), v);
        }
        q = q.add(4 * P);
    }
    // The partial last run: fewer than 4P words, so fewer than P vectors.
    let left = nwords - c0 - runs * 4 * P;
    for v in 0..left / 4 {
        or4::<P, INIT>(q.add(4 * v), v);
    }
    let v = left / 4;
    for l in 0..left % 4 {
        let a = q.add(4 * v + l);
        let x = if INIT { 0 } else { *a };
        *a = x | Dense::<P>::MASKS[v][l];
    }
    let f = P / 2; // P itself is prime
    if f >> 6 < nwords {
        *w.add(f >> 6) &= !(1u64 << (f & 63));
    }
}


/// The eight single-bit byte masks for factors p with p mod 16 = E: the multiple p(2j + 1) sits
/// at bit p/2 + jp, whose position within its byte is (E/2 + jE) mod 8.
struct SparseMasks<const E: usize>;

impl<const E: usize> SparseMasks<E> {
    const M: [u8; 8] = {
        let mut m = [0u8; 8];
        let mut j = 0;
        while j < 8 {
            m[j] = 1 << ((E / 2 + j * E) & 7);
            j += 1;
        }
        m
    };
}

/// Sparse clearing over bytes for an odd factor p >= 128 with p mod 16 = E. Chunks of p bytes
/// start at byte multiples of p; in each, the eight multiples sit at fixed byte offsets.
///
/// # Safety
/// `b` points to `nbytes` initialised bytes, p mod 16 = E and p² <= the sieve size.
#[inline(always)]
unsafe fn clear_sparse<const E: usize>(b: *mut u8, nbytes: usize, p: usize) {
    debug_assert_eq!(p & 15, E);
    let m = SparseMasks::<E>::M;
    let h = p / 2;
    let o = [
        h >> 3,
        (h + p) >> 3,
        (h + 2 * p) >> 3,
        (h + 3 * p) >> 3,
        (h + 4 * p) >> 3,
        (h + 5 * p) >> 3,
        (h + 6 * p) >> 3,
        (h + 7 * p) >> 3,
    ];
    let s0 = (p * p / 2) / 8 / p * p;
    debug_assert!(s0 < nbytes);
    let chunks = (nbytes - s0) / p;
    let mut q = b.add(s0);
    // SAFETY: every offset o[j] is below p, and the loop visits only the `chunks` whole chunks
    // that end at or before `nbytes`, so every byte written is inside the buffer.
    for _ in 0..chunks {
        *q.add(o[0]) |= m[0]; // one composite each
        *q.add(o[1]) |= m[1];
        *q.add(o[2]) |= m[2];
        *q.add(o[3]) |= m[3];
        *q.add(o[4]) |= m[4];
        *q.add(o[5]) |= m[5];
        *q.add(o[6]) |= m[6];
        *q.add(o[7]) |= m[7];
        q = q.add(p);
    }
    // Partial last chunk: the offsets increase, so stop at the first one past the end.
    let left = nbytes - s0 - chunks * p;
    for j in 0..8 {
        if o[j] >= left {
            break;
        }
        *q.add(o[j]) |= m[j];
    }
}

fn sieve_count(size: u64) -> usize {
    let mut sieve = Sieve::new(size);
    sieve.run();
    sieve.count_primes()
}

/// Passes completed before the deadline, and the prime count from the first pass.
fn worker(deadline: Instant) -> (u64, usize) {
    let mut passes = 0;
    let mut count = 0;
    while Instant::now() < deadline {
        let mut sieve = Sieve::new(SIEVE_SIZE);
        sieve.run();
        if passes == 0 {
            count = sieve.count_primes();
        }
        passes += 1;
    }
    (passes, count)
}

/// One timed run on `threads` threads, each running its own sieves. Returns false if any thread
/// got a wrong count.
fn timed_run(threads: usize) -> bool {
    let start = Instant::now();
    let deadline = start + RUN_TIME;
    let results: Vec<(u64, usize)> = if threads == 1 {
        vec![worker(deadline)]
    } else {
        thread::scope(|s| {
            let handles: Vec<_> = (0..threads)
                .map(|_| s.spawn(move || worker(deadline)))
                .collect();
            handles.into_iter().map(|h| h.join().unwrap()).collect()
        })
    };
    let elapsed = start.elapsed().as_secs_f64();
    if results.iter().any(|&(_, count)| count != EXPECTED) {
        eprintln!("ERROR: wrong prime count");
        return false;
    }
    let passes: u64 = results.iter().map(|&(p, _)| p).sum();
    println!("{LABEL};{passes};{elapsed:.6};{threads};{TAGS}");
    true
}

/// PRIMES_TEST=1: prime counts for every power of ten from 10 to 10^8 and a few awkward sizes.
fn self_test() -> bool {
    const CASES: [(u64, usize); 13] = [
        (1, 0),
        (2, 1),
        (3, 2),
        (10, 4),
        (100, 25),
        (1_000, 168),
        (10_000, 1_229),
        (100_000, 9_592),
        (1_000_000, 78_498),
        (10_000_000, 664_579),
        (100_000_000, 5_761_455),
        (127, 31),
        (16_383, 1_900),
    ];
    let mut ok = true;
    for (size, expected) in CASES {
        let c = sieve_count(size);
        println!(
            "size {size} -> {c} primes (expected {expected}) {}",
            u8::from(c == expected)
        );
        ok &= c == expected;
    }
    ok
}

fn main() -> ExitCode {
    let test = env::var("PRIMES_TEST").ok().and_then(|v| v.trim().parse::<u32>().ok());
    if test.is_some_and(|v| v != 0) {
        return if self_test() { ExitCode::SUCCESS } else { ExitCode::FAILURE };
    }

    // Threads this process may run on. On Linux this counts the CPUs in the affinity mask
    // (and honours a cgroup CPU quota), so a container limited with --cpuset-cpus is not
    // oversubscribed.
    let hw = thread::available_parallelism().map_or(1, |n| n.get());

    // One thread, then all, half and a quarter of the hardware threads: where SMT siblings
    // share an L1 cache, fewer threads can finish more passes.
    let mut runs = vec![1];
    let mut n = hw;
    while n >= 2 && n * 4 >= hw {
        runs.push(n);
        n /= 2;
    }
    for threads in runs {
        if !timed_run(threads) {
            return ExitCode::FAILURE;
        }
    }
    ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every size from 1 to 20,000 and every 997th to 2,000,000 against a plain sieve.
    #[test]
    fn matches_reference() {
        const LIMIT: usize = 2_000_000;
        let mut prime = vec![true; LIMIT + 1];
        prime[..2].fill(false);
        let mut i = 2;
        while i * i <= LIMIT {
            if prime[i] {
                (i * i..=LIMIT).step_by(i).for_each(|j| prime[j] = false);
            }
            i += 1;
        }
        let mut pi = vec![0usize; LIMIT + 1];
        for n in 1..=LIMIT {
            pi[n] = pi[n - 1] + usize::from(prime[n]);
        }
        for size in (0..20_000).chain((20_000..=LIMIT).step_by(997)) {
            assert_eq!(sieve_count(size as u64), pi[size], "size {size}");
        }
    }
}
