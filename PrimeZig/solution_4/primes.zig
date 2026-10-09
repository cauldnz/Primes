// Prime sieve drag race - Zig solution by cauldnz.
//
// One program, two entries:
//
//  * cauldnz-zig-base: the base algorithm, one bit per odd number. Every composite is cleared
//    by its own single-bit OR in the source. Factors below 128 use dense resetters generated at
//    compile time, one per odd factor; larger factors use a byte resetter whose masks are
//    compile-time constants chosen by p mod 16.
//  * cauldnz-zig-wheel: a mod-30 wheel with 8 bit-planes, a 7*11 pattern tile, fused word
//    patterns for primes below 256 and strided bit sets above. It ports the structure of the
//    author's ISPC wheel entry (PrimeISPC/solution_1) to Zig vectors.
//
// Both run single-threaded, then on all, half and a quarter of the hardware threads.

const std = @import("std");

const Allocator = std.mem.Allocator;

const SIEVE_SIZE: u64 = 1_000_000;
const EXPECTED: usize = 78498;
const RUN_NS: u64 = 5 * std.time.ns_per_s;

// Words per vector step, from the target's native u64 vector width (2 for SSE2 and NEON, 4 for
// AVX2, 8 for AVX-512). The base resetter was within noise from one to four registers' worth,
// so it uses two. The wheel's fused loop updates a scalar phase per pattern per step, and wider
// steps spread that cost: on a Xeon, SSE2 ran 18% faster with eight words than with four, and
// AVX2 and AVX-512 gained again from 16 to 32 words. The wheel uses eight registers' worth,
// capped at 32 words.
const NATIVE: usize = std.simd.suggestVectorLength(u64) orelse 1;
const VB: usize = 2 * NATIVE;
const VW: usize = @min(8 * NATIVE, 32);

fn Words(comptime n: usize) type {
    return @Vector(n, u64);
}

inline fn loadV(comptime n: usize, p: [*]const u64) Words(n) {
    return @as(*align(8) const Words(n), @ptrCast(p)).*;
}

inline fn storeV(comptime n: usize, p: [*]u64, v: Words(n)) void {
    @as(*align(8) Words(n), @ptrCast(p)).* = v;
}

fn isqrt(n: u64) u64 {
    return std.math.sqrt(n);
}

// =========================================================================================
// Base algorithm
// =========================================================================================

const DENSE_LIMIT: usize = 128; // odd factors below this get a dense resetter

// Smallest j >= 0 with P/2 + j*P >= lo: the first multiple at or after bit lo.
fn firstMultiple(comptime P: usize, comptime lo: usize) usize {
    return if (lo <= P / 2) 0 else (lo - P / 2 + P - 1) / P;
}

// A vector of VB words with one bit set: bit `off` counted across the whole vector.
fn laneBit(comptime off: usize) Words(VB) {
    var a = [_]u64{0} ** VB;
    a[off >> 6] = @as(u64, 1) << (off & 63);
    return a;
}

// Dense resetter for a compile-time odd factor P. Bit i stands for 2i+1, so the odd multiples
// of P sit at bits P/2 + j*P. They repeat every P words, 64 to a period, at the same word and
// bit offsets, so with P known at compile time every offset and mask is a constant.
// Each word (or vector of VB words) is loaded once, then each composite in it gets its own
// single-bit OR, then it is stored. LLVM folds the constant ORs.
// Clearing starts at the period holding P*P; the smaller multiples there are composite too,
// except P itself, which is restored at the end.
fn denseReset(comptime P: usize, w: []u64) void {
    @setEvalBranchQuota(100_000);
    const len = w.len;
    const ptr = w.ptr;
    var c: usize = ((P * P / 2) / 64 / P) * P;

    // Blocks of VB periods: P vectors of VB consecutive words.
    while (c + VB * P <= len) : (c += VB * P) {
        inline for (0..P) |vi| {
            const lo = 64 * VB * vi; // first bit of this vector within the block
            var x = loadV(VB, ptr + c + VB * vi);
            comptime var j = firstMultiple(P, lo);
            inline while (P / 2 + j * P < lo + 64 * VB) : (j += 1) {
                x |= comptime laneBit(P / 2 + j * P - lo); // one composite
            }
            storeV(VB, ptr + c + VB * vi, x);
        }
    }
    // Whole periods left over, a word at a time.
    while (c + P <= len) : (c += P) {
        inline for (0..P) |k| {
            var x = ptr[c + k];
            comptime var j = firstMultiple(P, 64 * k);
            inline while (P / 2 + j * P < 64 * (k + 1)) : (j += 1) {
                x |= @as(u64, 1) << ((P / 2 + j * P) & 63); // one composite
            }
            ptr[c + k] = x;
        }
    }
    // The partial last period.
    inline for (0..64) |j| {
        const t = P / 2 + j * P;
        if (c + (t >> 6) < len) ptr[c + (t >> 6)] |= @as(u64, 1) << (t & 63);
    }
    const f = P / 2; // P itself
    if ((f >> 6) < len) ptr[f >> 6] &= ~(@as(u64, 1) << (f & 63));
}

// Sparse resetter over bytes for an odd factor p >= 128. In each run of p bytes the 8 odd
// multiples sit at bit offsets p/2 + j*p (j = 0..7). Their bit-in-byte positions depend only on
// E = p mod 16, so the masks are compile-time constants; the byte offsets are computed per
// factor. A pointer walks the runs, one single-bit OR per composite.
fn sparseReset(comptime E: usize, bytes: []u8, p: usize) void {
    const h = p / 2;
    const o = [8]usize{ h >> 3, (h + p) >> 3, (h + 2 * p) >> 3, (h + 3 * p) >> 3, (h + 4 * p) >> 3, (h + 5 * p) >> 3, (h + 6 * p) >> 3, (h + 7 * p) >> 3 };
    const m = comptime blk: {
        var a: [8]u8 = undefined;
        for (0..8) |j| a[j] = @as(u8, 1) << @intCast((E / 2 + j * E) & 7);
        break :blk a;
    };
    const first = ((p * p / 2) / 8 / p) * p;
    if (first >= bytes.len) return;
    var q: [*]u8 = bytes.ptr + first;
    var runs = (bytes.len - first) / p;
    while (runs > 0) : (runs -= 1) {
        q[o[0]] |= m[0];
        q[o[1]] |= m[1];
        q[o[2]] |= m[2];
        q[o[3]] |= m[3];
        q[o[4]] |= m[4];
        q[o[5]] |= m[5];
        q[o[6]] |= m[6];
        q[o[7]] |= m[7];
        q += p;
    }
    const left = bytes.len - (@intFromPtr(q) - @intFromPtr(bytes.ptr)); // partial last run
    inline for (0..8) |j| {
        if (o[j] >= left) return;
        q[o[j]] |= m[j];
    }
}

const BaseSieve = struct {
    alloc: Allocator,
    size: u64, // find primes up to and including this number
    nbits: usize, // one bit per odd number 1, 3, 5, ... <= size
    words: []align(64) u64, // a set bit means composite

    fn init(alloc: Allocator, size: u64) !BaseSieve {
        const nbits: usize = @intCast((size + 1) / 2);
        // Cache-line aligned: the arena's own header left the words 16 bytes past a line, so
        // half the 32-byte and every 64-byte dense vector access split a cache line.
        const words = try alloc.alignedAlloc(u64, 64, (nbits + 63) / 64);
        @memset(words, 0);
        return .{ .alloc = alloc, .size = size, .nbits = nbits, .words = words };
    }

    fn deinit(self: *BaseSieve) void {
        self.alloc.free(self.words);
    }

    inline fn isComposite(self: *const BaseSieve, i: usize) bool {
        return (self.words[i >> 6] >> @intCast(i & 63)) & 1 != 0;
    }

    fn clearFactor(self: *BaseSieve, p: usize) void {
        if (p < DENSE_LIMIT) {
            // Every odd factor below 128 has its own resetter, composite factors included,
            // so nothing is assumed about which numbers are prime.
            switch (p) {
                inline 3...DENSE_LIMIT - 1 => |P| {
                    if (P % 2 == 1) denseReset(P, self.words) else unreachable;
                },
                else => unreachable,
            }
            return;
        }
        // The byte view of the words. Both supported targets are little-endian, so byte b
        // bit k is bit 8b+k of the sieve.
        const bytes = std.mem.sliceAsBytes(self.words);
        switch (p & 15) {
            inline 1, 3, 5, 7, 9, 11, 13, 15 => |E| sparseReset(E, bytes, p),
            else => unreachable,
        }
    }

    // The base algorithm: find the next prime by checking odd numbers from 3, clear its odd
    // multiples, repeat up to the square root of the size.
    fn run(self: *BaseSieve) void {
        const q = isqrt(self.size);
        var factor: usize = 3;
        while (factor <= q) {
            var i = factor >> 1;
            while (i < self.nbits and self.isComposite(i)) i += 1;
            factor = 2 * i + 1;
            if (factor > q) break;
            self.clearFactor(factor);
            factor += 2;
        }
    }

    // Primes up to and including size: unmarked odd numbers 3..size, plus 2.
    fn count(self: *const BaseSieve) usize {
        if (self.size < 2) return 0;
        var c: usize = 1;
        for (1..self.nbits) |i| {
            if (!self.isComposite(i)) c += 1;
        }
        return c;
    }
};

// =========================================================================================
// Wheel algorithm
// =========================================================================================

const G: usize = 8; // primes fused into one pass over a plane
const MAXPAT: usize = 1024; // longest pattern period, in words
const DENSE_MAX: u32 = 256; // primes below this are applied as word patterns

const RES = [8]u32{ 1, 7, 11, 13, 17, 19, 23, 29 };
// plane of n % 30, or -1 when n shares a factor with 30
const PLANE = [30]i8{ -1, 0, -1, -1, -1, -1, -1, 1, -1, -1, -1, 2, -1, 3, -1, -1, -1, 4, -1, 5, -1, -1, -1, 6, -1, -1, -1, -1, -1, 7 };
// multiplicative inverse mod 30, for residues coprime to 30
const INV30 = [30]u32{ 0, 1, 0, 0, 0, 0, 0, 13, 0, 0, 0, 11, 0, 7, 0, 0, 0, 23, 0, 19, 0, 0, 0, 17, 0, 0, 0, 0, 0, 29 };

// Word patterns for a group of up to G primes, built once and shared by all 8 planes.
const Group = struct {
    L: [G]usize, // pattern period in words: a multiple of p, at least VW
    tab: [G][64]u16, // starting phase for each bit offset
    buf: [G][MAXPAT + 64]u64, // the patterns, extended by VW words past L
};

// First bit in plane R of a multiple p*k with k >= kmin.
fn startBit(p: u32, R: u32, kmin: u32) usize {
    const kr = (R * INV30[p % 30]) % 30; // k must be kr (mod 30)
    const k: u64 = kmin + ((kr + 30 - kmin % 30) % 30);
    return @intCast((@as(u64, p) * k - R) / 30);
}

// One period of p's stride-p pattern, extended to L + VW words. Any bit offset of the pattern
// is a whole-word rotation of it, since 64 is invertible mod p; tab[t] is the word whose bit t
// is set, which is the starting phase for offset t.
fn buildPattern(pat: []u64, tab: *[64]u16, p: usize) usize {
    var L = p;
    while (L < VW) L += p;
    @memset(pat[0..p], 0);
    var j: usize = 0;
    while (j < p * 64) : (j += p) {
        pat[j >> 6] |= @as(u64, 1) << @intCast(j & 63);
        tab[j & 63] = @intCast(j >> 6);
    }
    for (p..L + VW) |k| pat[k] = pat[k - p];
    return L;
}

// OR the N patterns of a group into words [start, nw) of one plane, where start is the first
// word any member touches. One load and one store per sieve vector for all N members. A
// member also marks its multiples below p*p in its first word, which are composite, and p
// itself, which the caller clears again. The last partial vector runs into the plane's padding.
fn applyGroup(comptime N: usize, w: [*]u64, nw: usize, g: *const Group, b: []const usize) void {
    var start: usize = nw;
    inline for (0..N) |j| start = @min(start, b[j] >> 6);
    var r: [N]usize = undefined;
    var pp: [N][*]const u64 = undefined;
    var L: [N]usize = undefined;
    inline for (0..N) |j| {
        L[j] = g.L[j];
        pp[j] = &g.buf[j];
        const back = ((b[j] >> 6) - start) % L[j];
        const t: usize = g.tab[j][b[j] & 63];
        r[j] = if (t >= back) t - back else t + L[j] - back;
    }
    var k = start;
    while (k + VW <= nw) : (k += VW) {
        var v = loadV(VW, w + k);
        inline for (0..N) |j| {
            v |= loadV(VW, pp[j] + r[j]);
            r[j] += VW;
            if (r[j] >= L[j]) r[j] -= L[j];
        }
        storeV(VW, w + k, v);
    }
    if (k < nw) {
        var v = loadV(VW, w + k);
        inline for (0..N) |j| v |= loadV(VW, pp[j] + r[j]);
        storeV(VW, w + k, v);
    }
}

const WheelSieve = struct {
    alloc: Allocator,
    size: u64,
    mbits: usize, // bits used per plane
    nw: usize, // words used per plane
    pw: usize, // plane stride in words
    bits: []align(64) u64, // the 8 bit-planes, pw words apart; a set bit means composite
    grp: *Group, // pattern scratch

    fn init(alloc: Allocator, size: u64) !WheelSieve {
        const mbits: usize = @intCast(size / 30 + 1);
        const nw = (mbits + 63) / 64;
        const pw = (nw + VW - 1 + 7) & ~@as(usize, 7); // room for the last vector to overrun
        const bits = try alloc.alignedAlloc(u64, 64, 8 * pw);
        const grp = try alloc.create(Group);
        for (0..8) |pl| @memset(bits[pl * pw + nw .. (pl + 1) * pw], 0);
        return .{ .alloc = alloc, .size = size, .mbits = mbits, .nw = nw, .pw = pw, .bits = bits, .grp = grp };
    }

    fn deinit(self: *WheelSieve) void {
        self.alloc.destroy(self.grp);
        self.alloc.free(self.bits);
    }

    fn plane(self: *WheelSieve, pl: usize) [*]u64 {
        return self.bits.ptr + pl * self.pw;
    }

    fn buildGroup(self: *WheelSieve, primes: []const u32) void {
        for (primes, 0..) |p, j| self.grp.L[j] = buildPattern(&self.grp.buf[j], &self.grp.tab[j], p);
    }

    fn apply(self: *WheelSieve, w: [*]u64, nw: usize, b: []const usize) void {
        switch (b.len) {
            inline 1...G => |N| applyGroup(N, w, nw, self.grp, b),
            else => unreachable,
        }
    }

    // Apply a group of primes, from p*p on, to all 8 planes.
    fn densePrimes(self: *WheelSieve, primes: []const u32) void {
        self.buildGroup(primes);
        var b: [G]usize = undefined;
        for (0..8) |pl| {
            for (primes, 0..) |p, j| b[j] = startBit(p, RES[pl], p);
            self.apply(self.plane(pl), self.nw, b[0..primes.len]);
        }
        for (primes) |p| { // each member marked itself
            const m = p / 30;
            if (m < self.mbits) {
                const pl: usize = @intCast(PLANE[p % 30]);
                self.plane(pl)[m >> 6] &= ~(@as(u64, 1) << @intCast(m & 63));
            }
        }
    }

    // Large primes: at most one bit per word. All 8 planes advance together, giving 8
    // independent read-modify-write streams per round.
    fn sparsePrime(self: *WheelSieve, p: u32) void {
        const nbits = self.mbits;
        const base = self.bits.ptr;
        var i: [8]usize = undefined;
        var hi: usize = 0;
        for (0..8) |pl| {
            const sb = startBit(p, RES[pl], p);
            hi = @max(hi, sb);
            i[pl] = sb + pl * self.pw * 64; // bit index in the whole buffer
        }
        var rounds: usize = if (hi < nbits) (nbits - 1 - hi) / p + 1 else 0;
        while (rounds > 0) : (rounds -= 1) {
            inline for (0..8) |pl| {
                base[i[pl] >> 6] |= @as(u64, 1) << @intCast(i[pl] & 63);
                i[pl] += p;
            }
        }
        for (0..8) |pl| {
            const end = pl * self.pw * 64 + nbits;
            var x = i[pl];
            while (x < end) : (x += p) base[x >> 6] |= @as(u64, 1) << @intCast(x & 63);
        }
    }

    fn isComposite(self: *WheelSieve, n: usize) bool {
        const m = n / 30;
        const w = self.plane(@intCast(PLANE[n % 30]));
        return (w[m >> 6] >> @intCast(m & 63)) & 1 != 0;
    }

    fn run(self: *WheelSieve) void {
        const nw = self.nw;

        // Phase 1: the wheel tile. Multiples of 7 and 11 repeat every 77 words in each plane,
        // so mark one period, starting from 7 and 11 themselves to keep it periodic, and copy
        // it along the plane. 7 and 11 are then unmarked.
        const t = @min(77, nw);
        const tp = [2]u32{ 7, 11 };
        self.buildGroup(&tp);
        for (0..8) |pl| {
            const w = self.plane(pl);
            @memset(w[0..t], 0);
            const tb = [2]usize{ startBit(7, RES[pl], 1), startBit(11, RES[pl], 1) };
            applyGroup(2, w, t, self.grp, &tb);
            var base: usize = t;
            while (base < nw) : (base += t) {
                const n = @min(t, nw - base);
                @memcpy(w[base .. base + n], w[0..n]);
            }
        }
        self.plane(0)[0] |= 1; // 1 is not prime
        self.plane(1)[0] &= ~@as(u64, 1); // 7 is prime
        self.plane(2)[0] &= ~@as(u64, 1); // 11 is prime

        // Phase 2: 13 on its own. Afterwards every bit below 17*17 is final.
        const thirteen = [1]u32{13};
        self.densePrimes(&thirteen);

        // Phase 3: the remaining primes up to sqrt(size), small ones as fused pattern groups,
        // large ones as strided bit sets. A candidate is read only once every prime up to its
        // square root has been applied: c < g0*g0 for the smallest prime g0 still pending.
        const q = isqrt(self.size);
        var grp: [G]u32 = undefined;
        var n: usize = 0;
        var c: u32 = 17;
        while (c <= q) : (c += 2) {
            if (PLANE[c % 30] < 0) continue;
            if (n > 0 and (c >= DENSE_MAX or c >= grp[0] * grp[0])) {
                self.densePrimes(grp[0..n]);
                n = 0;
            }
            if (self.isComposite(c)) continue;
            if (c < DENSE_MAX) {
                grp[n] = c;
                n += 1;
                if (n == G) {
                    self.densePrimes(grp[0..n]);
                    n = 0;
                }
            } else {
                self.sparsePrime(c);
            }
        }
        if (n > 0) self.densePrimes(grp[0..n]);
    }

    // Primes up to and including size: unmarked bits for numbers <= size, plus 2, 3 and 5.
    fn count(self: *WheelSieve) usize {
        const size = self.size;
        var c: usize = @as(usize, @intFromBool(size >= 2)) + @intFromBool(size >= 3) + @intFromBool(size >= 5);
        for (0..8) |pl| {
            if (size < RES[pl]) continue;
            const w = self.plane(pl);
            const mmax: usize = @intCast((size - RES[pl]) / 30); // last bit <= size
            for (0..self.nw) |k| {
                const lo = k << 6;
                if (lo > mmax) break;
                var x = ~w[k];
                if (lo + 63 > mmax) x &= ~@as(u64, 0) >> @intCast(63 - (mmax - lo));
                c += @popCount(x);
            }
        }
        return c;
    }
};

// =========================================================================================
// Benchmark driver
// =========================================================================================

const Job = struct {
    start: std.time.Instant, // the run ends RUN_NS after this
    passes: u64 = 0,
    count: usize = 0, // prime count from the first pass, for validation
};

fn fatal(comptime msg: []const u8) noreturn {
    std.io.getStdErr().writer().print("ERROR: " ++ msg ++ "\n", .{}) catch {};
    std.process.exit(1);
}

fn now() std.time.Instant {
    return std.time.Instant.now() catch fatal("no monotonic clock");
}

// Each pass creates a fresh sieve, runs it and frees it; nothing is kept between passes.
// Each thread allocates from its own arena over page memory, which hands back the same pages
// once a pass has freed them, as a thread-caching malloc would. musl's malloc, which the
// Alpine image would otherwise use, cost 20% at one thread and serialised the threads.
// Every sieve writes all of its memory before reading it.
fn worker(comptime S: type, job: *Job) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var passes: u64 = 0;
    var count: usize = 0;
    while (now().since(job.start) < RUN_NS) {
        var s = S.init(arena.allocator(), SIEVE_SIZE) catch fatal("out of memory");
        s.run();
        if (passes == 0) count = s.count();
        s.deinit();
        _ = arena.reset(.retain_capacity);
        passes += 1;
    }
    job.passes = passes;
    job.count = count;
}

fn runEntry(comptime S: type, comptime label: []const u8, comptime tags: []const u8, nthreads: usize) !void {
    const out = std.io.getStdOut().writer();
    var jobs: [1024]Job = undefined;
    var threads: [1024]std.Thread = undefined;

    // single-threaded, then all, half and a quarter of the hardware threads
    var n: usize = 1;
    var next: usize = nthreads;
    while (true) {
        const start = now();
        if (n == 1) {
            jobs[0] = .{ .start = start };
            worker(S, &jobs[0]);
        } else {
            for (0..n) |t| {
                jobs[t] = .{ .start = start };
                threads[t] = try std.Thread.spawn(.{}, worker, .{ S, &jobs[t] });
            }
            for (0..n) |t| threads[t].join();
        }
        const elapsed = @as(f64, @floatFromInt(now().since(start))) / std.time.ns_per_s;
        var total: u64 = 0;
        for (jobs[0..n]) |j| {
            if (j.count != EXPECTED) fatal("wrong prime count");
            total += j.passes;
        }
        try out.print(label ++ ";{d};{d:.6};{d};" ++ tags ++ "\n", .{ total, elapsed, n });

        if (next < 2 or next * 4 < nthreads) break;
        n = next;
        next /= 2;
    }
}

fn selfTest(comptime S: type, comptime name: []const u8, sizes: []const u64, expect: []const usize) bool {
    const err = std.io.getStdErr().writer();
    var ok = true;
    for (sizes, expect) |size, e| {
        var s = S.init(std.heap.page_allocator, size) catch fatal("out of memory");
        s.run();
        const c = s.count();
        s.deinit();
        err.print("{s}: size {d} -> {d} primes (expected {d}) {s}\n", .{ name, size, c, e, if (c == e) "ok" else "FAIL" }) catch {};
        if (c != e) ok = false;
    }
    return ok;
}

pub fn main() !void {
    if (std.posix.getenv("PRIMES_TEST")) |v| {
        if (!std.mem.eql(u8, v, "0") and v.len > 0) {
            const pow10 = [_]u64{ 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000 };
            const pow10_expect = [_]usize{ 4, 25, 168, 1229, 9592, 78498, 664579, 5761455 };
            const edge = [_]u64{ 1, 2, 3, 127, 16383 };
            const edge_expect = [_]usize{ 0, 1, 2, 31, 1900 };
            var ok = selfTest(BaseSieve, "base", &pow10, &pow10_expect);
            ok = selfTest(BaseSieve, "base", &edge, &edge_expect) and ok;
            ok = selfTest(WheelSieve, "wheel", &pow10, &pow10_expect) and ok;
            ok = selfTest(WheelSieve, "wheel", &edge, &edge_expect) and ok;
            std.process.exit(if (ok) 0 else 1);
        }
    }

    const nthreads = @min(@max(std.Thread.getCpuCount() catch 1, 1), 1024);
    try runEntry(BaseSieve, "cauldnz-zig-base", "algorithm=base,faithful=yes,bits=1", nthreads);
    try runEntry(WheelSieve, "cauldnz-zig-wheel", "algorithm=wheel,faithful=yes,bits=1", nthreads);
}
