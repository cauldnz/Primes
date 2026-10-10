//! Prime sieve drag race: a Rust wheel solution by cauldnz.
//!
//! A sieve of Eratosthenes on a mod-30 wheel. Only numbers coprime to 30 are stored, as eight
//! bit-planes, one per residue R in {1, 7, 11, 13, 17, 19, 23, 29}: bit m of plane R stands for
//! 30m + R, and a set bit means composite. Within one plane the multiples of a prime p step
//! through the bits with stride p, so each (prime, plane) pair is a plain stride-p sieve whose
//! word pattern repeats every p words.
//!
//! Small primes stream those repeating word patterns into the planes, several primes fused into
//! one pass over each plane. Large primes set single bits, eight planes at a time.

use std::env;
use std::process::ExitCode;
use std::thread;
use std::time::{Duration, Instant};

const SIEVE_SIZE: u64 = 1_000_000;
const EXPECTED: usize = 78_498;
const RUN_TIME: Duration = Duration::from_secs(5);
const LABEL: &str = "cauldnz-rust-wheel";
const TAGS: &str = "algorithm=wheel,faithful=yes,bits=1";

/// Words per step of the fused pattern loop. The loop body is written over `[u64; VW]` arrays
/// and LLVM turns it into vector loads and stores. A step wider than one register keeps more
/// independent loads in flight and spreads the per-step phase updates over more words.
const VW: usize = 32;
/// Primes fused into one pass over a plane.
const G: usize = 8;
/// Primes below this are applied as word patterns, larger ones as single bits.
const DENSE_MAX: u32 = 256;
/// Upper limit for `PRIMES_DENSE_MAX`.
const DENSE_LIMIT: u32 = 1024;
/// Multiples of 7 and 11 repeat every 77 words in every plane.
const TILE: usize = 77;

const RES: [u32; 8] = [1, 7, 11, 13, 17, 19, 23, 29];
/// Plane of n % 30, or -1 when n shares a factor with 30.
const PLANE: [i8; 30] = [
    -1, 0, -1, -1, -1, -1, -1, 1, -1, -1, -1, 2, -1, 3, -1, -1, -1, 4, -1, 5, -1, -1, -1, 6, -1,
    -1, -1, -1, -1, 7,
];
/// Multiplicative inverse mod 30, for residues coprime to 30.
const INV30: [u32; 30] = [
    0, 1, 0, 0, 0, 0, 0, 13, 0, 0, 0, 11, 0, 7, 0, 0, 0, 23, 0, 19, 0, 0, 0, 17, 0, 0, 0, 0, 0, 29,
];

/// First bit in plane `r` of a multiple p*k with k >= kmin.
fn start_bit(p: u32, r: u32, kmin: u32) -> usize {
    let kr = (r * INV30[(p % 30) as usize]) % 30; // k must be kr (mod 30)
    let k = u64::from(kmin + (kr + 30 - kmin % 30) % 30);
    ((u64::from(p) * k - u64::from(r)) / 30) as usize
}

/// One group member's word pattern, held in `Sieve::rows`.
#[derive(Clone, Copy)]
struct Pattern {
    /// Index in `rows` of the pattern's first word.
    first: usize,
    /// Period in words: a multiple of p, at least `VW`. The row holds `period + VW` words, so a
    /// step that starts anywhere in the period reads whole.
    period: usize,
    /// For each bit offset t, the word whose bit t is set: the phase to start at for offset t.
    tab: [u16; 64],
}

impl Pattern {
    const EMPTY: Pattern = Pattern {
        first: 0,
        period: 1,
        tab: [0; 64],
    };

    /// Appends the pattern of p to `rows`: one period of p words with a bit at every multiple
    /// of p, then copies of it out to `period + VW` words. Any bit offset of a stride-p pattern
    /// is a whole-word rotation of this one, since 64 is invertible mod p, so this one row
    /// serves every plane.
    fn push(rows: &mut Vec<u64>, p: usize) -> Pattern {
        let first = rows.len();
        let mut tab = [0u16; 64];
        let mut j = 0; // next multiple of p, as a bit index; 64 of them in p words
        for k in 0..p {
            let mut word = 0u64;
            while j < 64 * (k + 1) {
                word |= 1 << (j & 63);
                tab[j & 63] = k as u16;
                j += p;
            }
            rows.push(word);
        }
        let period = p * VW.div_ceil(p);
        while rows.len() - first < period + VW {
            let n = p.min(period + VW - (rows.len() - first));
            rows.extend_from_within(first..first + n);
        }
        Pattern { first, period, tab }
    }
}

/// ORs the patterns of N primes into words [start, nw) of one plane, where start is the first
/// word any member touches. Each sieve word is loaded and stored once for all N members.
///
/// Every member starts at the same word, so none needs a lead-in. A member then also marks its
/// multiples below p*p in that word, which are composite, and p itself, which the caller clears
/// again. The last partial step runs on into the plane's padding: the extra words get the same
/// patterns, which is harmless there.
fn apply_group<const N: usize>(
    plane: &mut [u64],
    nw: usize,
    rows: &[u64],
    members: &[Pattern; N],
    b: &[usize; N],
) {
    let start = b.iter().map(|&x| x >> 6).min().unwrap_or(nw);
    // Each member's phase is an index into `rows`, so the loop keeps one register per member.
    let mut r = [0usize; N];
    let mut end = [0usize; N];
    let mut period = [0usize; N];
    for j in 0..N {
        let m = &members[j];
        let back = ((b[j] >> 6) - start) % m.period;
        let t = usize::from(m.tab[b[j] & 63]);
        r[j] = m.first
            + if t >= back {
                t - back
            } else {
                t + m.period - back
            };
        end[j] = m.first + m.period;
        period[j] = m.period;
    }
    let mut k = start;
    while k < nw {
        let w: &mut [u64; VW] = (&mut plane[k..k + VW]).try_into().unwrap();
        let mut v = *w;
        for j in 0..N {
            let pat: &[u64; VW] = rows[r[j]..r[j] + VW].try_into().unwrap();
            for i in 0..VW {
                v[i] |= pat[i];
            }
            r[j] += VW;
            if r[j] >= end[j] {
                r[j] -= period[j];
            }
        }
        *w = v;
        k += VW;
    }
}

/// All of one sieve's state. A new one is made for every pass.
struct Sieve {
    size: u64,
    /// Bits used per plane.
    mbits: usize,
    /// Words used per plane.
    nw: usize,
    /// Plane stride in words: a whole number of cache lines, with room for the last step of
    /// the fused loop to run past `nw`.
    pw: usize,
    /// Primes below this are applied as word patterns.
    dense_max: u32,
    /// The eight planes, `pw` words apart, starting at `base` (the first cache-line boundary).
    words: Vec<u64>,
    base: usize,
    /// Pattern rows for the current group, and where each member's row starts.
    rows: Vec<u64>,
    group: [Pattern; G],
}

impl Sieve {
    fn new(size: u64, dense_max: u32) -> Sieve {
        let mbits = (size / 30 + 1) as usize;
        let nw = mbits.div_ceil(64);
        let pw = (nw + VW - 1).next_multiple_of(8);
        let dense_max = dense_max.min(DENSE_LIMIT);
        Sieve {
            size,
            mbits,
            nw,
            pw,
            dense_max,
            // Filled by the first phase of `run`, which writes every word once.
            words: Vec::with_capacity(8 * pw + 7),
            base: 0,
            rows: Vec::with_capacity(G * (dense_max as usize + 2 * VW)),
            group: [Pattern::EMPTY; G],
        }
    }

    fn plane(&self, pl: usize) -> &[u64] {
        &self.words[self.base + pl * self.pw..][..self.pw]
    }

    fn plane_mut(&mut self, pl: usize) -> &mut [u64] {
        &mut self.words[self.base + pl * self.pw..][..self.pw]
    }

    fn is_composite(&self, n: u32) -> bool {
        let m = (n / 30) as usize;
        let w = self.plane(PLANE[(n % 30) as usize] as usize);
        (w[m >> 6] >> (m & 63)) & 1 != 0
    }

    fn clear_bit(&mut self, n: u32) {
        let m = (n / 30) as usize;
        if m < self.mbits {
            self.plane_mut(PLANE[(n % 30) as usize] as usize)[m >> 6] &= !(1 << (m & 63));
        }
    }

    fn build_group(&mut self, primes: &[u32]) {
        self.rows.clear();
        for (j, &p) in primes.iter().enumerate() {
            self.group[j] = Pattern::push(&mut self.rows, p as usize);
        }
    }

    /// Runs `apply_group` with the member count as a compile-time constant.
    fn apply(&mut self, pl: usize, nw: usize, b: &[usize]) {
        let plane = &mut self.words[self.base + pl * self.pw..][..self.pw];
        macro_rules! dispatch {
            ($($n:literal)*) => {
                match b.len() {
                    $($n => apply_group::<$n>(
                        plane,
                        nw,
                        &self.rows,
                        self.group[..$n].try_into().unwrap(),
                        b.try_into().unwrap(),
                    ),)*
                    _ => unreachable!(),
                }
            };
        }
        dispatch!(1 2 3 4 5 6 7 8);
    }

    /// Applies a group of primes, from p*p on, to all eight planes.
    fn dense_primes(&mut self, primes: &[u32]) {
        self.build_group(primes);
        let mut b = [0usize; G];
        for (pl, &r) in RES.iter().enumerate() {
            for (bj, &p) in b.iter_mut().zip(primes) {
                *bj = start_bit(p, r, p);
            }
            self.apply(pl, self.nw, &b[..primes.len()]);
        }
        for &p in primes {
            self.clear_bit(p); // each member marked itself
        }
    }

    /// Large primes set at most one bit per word. All eight planes advance together, giving
    /// eight independent read-modify-write streams per round.
    fn sparse_prime(&mut self, p: u32) {
        let (nbits, pw, step) = (self.mbits, self.pw, p as usize);
        let words = &mut self.words[self.base..];
        let mut i = [0usize; 8]; // bit index in the whole set of planes
        let mut hi = 0;
        for (pl, (ip, &r)) in i.iter_mut().zip(&RES).enumerate() {
            let sb = start_bit(p, r, p);
            hi = hi.max(sb);
            *ip = sb + pl * pw * 64;
        }
        // rounds in which all eight streams are still inside their planes
        let rounds = if hi < nbits {
            (nbits - 1 - hi) / step + 1
        } else {
            0
        };
        // This is the hottest loop, and bounds checks on it cost 13% at one thread.
        assert!(words.len() >= 8 * pw);
        for _ in 0..rounds {
            for ip in &mut i {
                // SAFETY: `rounds` keeps every stream below its plane's bit `nbits`, so the
                // word index is below pl * pw + nw <= 8 * pw <= words.len().
                unsafe { *words.get_unchecked_mut(*ip >> 6) |= 1 << (*ip & 63) };
                *ip += step;
            }
        }
        for (pl, &ip) in i.iter().enumerate() {
            let end = pl * pw * 64 + nbits;
            for x in (ip..end).step_by(step) {
                words[x >> 6] |= 1 << (x & 63);
            }
        }
    }

    fn run(&mut self) {
        let (nw, pw) = (self.nw, self.pw);

        // Phase 1: the wheel tile. Multiples of 7 and 11 repeat every 77 words in every plane,
        // so mark one period, starting from 7 and 11 themselves to keep it periodic, and copy
        // it along the plane. This writes every word of every plane, padding included.
        let t = TILE.min(nw);
        self.build_group(&[7, 11]);
        let pad = self.words.as_ptr().align_offset(64);
        self.words.resize(pad, 0);
        self.base = pad;
        let mut tile = [0u64; TILE + VW];
        for &r in &RES {
            tile.fill(0);
            let b = [start_bit(7, r, 1), start_bit(11, r, 1)];
            apply_group::<2>(
                &mut tile,
                t,
                &self.rows,
                self.group[..2].try_into().unwrap(),
                &b,
            );
            let mut left = nw;
            while left > 0 {
                let n = left.min(t);
                self.words.extend_from_slice(&tile[..n]);
                left -= n;
            }
            self.words.resize(self.words.len() + pw - nw, 0);
        }
        self.plane_mut(0)[0] |= 1; // 1 is not prime
        self.clear_bit(7);
        self.clear_bit(11);

        // Phase 2: 13 on its own. Afterwards every bit below 17*17 is final.
        self.dense_primes(&[13]);

        // Phase 3: the remaining primes up to sqrt(size), small ones as fused pattern groups,
        // large ones as single bits. A candidate is read only once every prime up to its square
        // root has been applied: c < g0*g0 for the smallest prime g0 still pending.
        let q = self.size.isqrt() as u32;
        let mut grp = [0u32; G];
        let mut n = 0;
        for c in (17..=q).step_by(2) {
            if PLANE[(c % 30) as usize] < 0 {
                continue;
            }
            if n > 0 && (c >= self.dense_max || u64::from(c) >= u64::from(grp[0]).pow(2)) {
                self.dense_primes(&grp[..n]);
                n = 0;
            }
            if self.is_composite(c) {
                continue;
            }
            if c < self.dense_max {
                grp[n] = c;
                n += 1;
                if n == G {
                    self.dense_primes(&grp);
                    n = 0;
                }
            } else {
                self.sparse_prime(c);
            }
        }
        if n > 0 {
            self.dense_primes(&grp[..n]);
        }
    }

    /// Primes up to and including the size: unmarked bits for numbers <= size, plus 2, 3 and 5.
    fn count_primes(&self) -> usize {
        let size = self.size;
        let mut c = [2, 3, 5].iter().filter(|&&s| size >= s).count();
        for (pl, &r) in RES.iter().enumerate() {
            if size < u64::from(r) {
                continue;
            }
            let mmax = ((size - u64::from(r)) / 30) as usize; // last bit <= size
            for (k, &w) in self.plane(pl)[..=mmax >> 6].iter().enumerate() {
                let mut x = !w;
                if 64 * k + 63 > mmax {
                    x &= !0u64 >> (63 - (mmax - 64 * k));
                }
                c += x.count_ones() as usize;
            }
        }
        c
    }
}

fn sieve_count(size: u64, dense_max: u32) -> usize {
    let mut sieve = Sieve::new(size, dense_max);
    sieve.run();
    sieve.count_primes()
}

/// Passes completed before the deadline, and the prime count from the first pass.
fn worker(deadline: Instant, dense_max: u32) -> (u64, usize) {
    let mut passes = 0;
    let mut count = 0;
    while Instant::now() < deadline {
        let mut sieve = Sieve::new(SIEVE_SIZE, dense_max);
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
fn timed_run(threads: usize, dense_max: u32) -> bool {
    let start = Instant::now();
    let deadline = start + RUN_TIME;
    let results: Vec<(u64, usize)> = if threads == 1 {
        vec![worker(deadline, dense_max)]
    } else {
        thread::scope(|s| {
            let handles: Vec<_> = (0..threads)
                .map(|_| s.spawn(move || worker(deadline, dense_max)))
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

/// PRIMES_TEST=1: prime counts for every power of ten up to 10^8, then for 5,396 sizes from 1
/// to 399,812 (every size below 5,000, then every 997th) against a plain reference sieve.
fn self_test(dense_max: u32) -> bool {
    const POWERS: [(u64, usize); 8] = [
        (10, 4),
        (100, 25),
        (1_000, 168),
        (10_000, 1_229),
        (100_000, 9_592),
        (1_000_000, 78_498),
        (10_000_000, 664_579),
        (100_000_000, 5_761_455),
    ];
    let mut ok = true;
    for (size, expected) in POWERS {
        let c = sieve_count(size, dense_max);
        println!(
            "size {size} -> {c} primes (expected {expected}) {}",
            u8::from(c == expected)
        );
        ok &= c == expected;
    }

    const LIMIT: usize = 400_000;
    let mut prime = vec![true; LIMIT];
    prime[..2].fill(false);
    for i in (2..).take_while(|i| i * i < LIMIT) {
        if prime[i] {
            (i * i..LIMIT).step_by(i).for_each(|j| prime[j] = false);
        }
    }
    let pi: Vec<usize> = prime
        .iter()
        .scan(0, |n, &is_prime| {
            *n += usize::from(is_prime);
            Some(*n)
        })
        .collect();
    let sizes: Vec<usize> = (1..5_000).chain((5_000..LIMIT).step_by(997)).collect();
    let mut wrong = 0;
    for &size in &sizes {
        let c = sieve_count(size as u64, dense_max);
        if c != pi[size] {
            println!("size {size} -> {c} primes (expected {}) 0", pi[size]);
            wrong += 1;
        }
    }
    println!(
        "{} sizes from 1 to {} -> {wrong} wrong {}",
        sizes.len(),
        sizes[sizes.len() - 1],
        u8::from(wrong == 0)
    );
    ok && wrong == 0
}

fn env_u32(name: &str) -> Option<u32> {
    env::var(name).ok().and_then(|v| v.trim().parse().ok())
}

fn main() -> ExitCode {
    let dense_max = env_u32("PRIMES_DENSE_MAX").unwrap_or(DENSE_MAX);
    if env_u32("PRIMES_TEST").is_some_and(|v| v != 0) {
        return if self_test(dense_max) {
            ExitCode::SUCCESS
        } else {
            ExitCode::FAILURE
        };
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
        if !timed_run(threads, dense_max) {
            return ExitCode::FAILURE;
        }
    }
    ExitCode::SUCCESS
}
