// DIAGNOSTIC BUILD (hc/diag-swift-phases): never merge.
import Foundation
import ArgumentParser
import BenchmarkObserver

// Every timed pass allocates, initializes, calculates, observes, and releases its
// own sieve. The separate observer module keeps the completed storage observable.
@inline(never)
func completedPass(limit: Int, offset: Int) -> UInt64 {
    let sieve = PrimeSieve(limit: limit)
    sieve.runSieve()
    return sieve.withStorage { observe($0, at: offset) }
}

struct PrimeSieveSwift: ParsableCommand {
    public static let configuration = CommandConfiguration(abstract: "Generate Primes")

    @Option(name: [.customLong("upper-limit"), .customShort("n")], help: "Compute all primes below this limit.")
    private var upperLimit = 1_000_000

    @Option(name: [.customLong("time"), .customShort("t")], help: "Minimum running time in seconds.")
    private var maxTime = 5.0

    @Option(name: [.customLong("list-results"), .customShort("l")], help: "List all computed primes.")
    private var listResults = false

    func validate() throws {
        guard upperLimit >= 0 else {
            throw ValidationError("The upper limit must be nonnegative.")
        }
        _ = try validatedNanoseconds(for: maxTime)
    }

    func run() throws {
        let byteCount = PrimeSieve.storageLayout(for: upperLimit).byteCount
        let targetNanoseconds = try validatedNanoseconds(for: maxTime)
        var passes = 0
        var checksum: UInt64 = 0
        let start = DispatchTime.now().uptimeNanoseconds
        var elapsed: UInt64
        repeat {
            // withStorage passes nil to the observer when the sieve has no bytes.
            let offset = byteCount == 0 ? 0 : passes % byteCount
            checksum &+= completedPass(limit: upperLimit, offset: offset)
            passes += 1
            elapsed = DispatchTime.now().uptimeNanoseconds - start
        } while elapsed < targetNanoseconds
        let duration = Double(elapsed) / 1_000_000_000

        // Keep the benchmark's numeric bound unchanged. The class includes its
        // limit; the existing CLI lists and counts only primes below upperLimit.
        // Validation, enumeration, and printing are outside the timed interval.
        let check = PrimeSieve(limit: upperLimit)
        check.runSieve()
        let inclusivePrimes = check.primes()
        // Sorted inclusive output can exceed the CLI's exclusive bound only at
        // its final element. Keep a slice instead of allocating a filtered array.
        let primes = inclusivePrimes.dropLast(inclusivePrimes.last == upperLimit ? 1 : 0)
        let primeCounts = [
                     10:         4,
                    100:        25,
                  1_000:       168,
                 10_000:     1_229,
                100_000:     9_592,
              1_000_000:    78_498,
             10_000_000:   664_579,
            100_000_000: 5_761_455,
        ]
        let valid = primeCounts[upperLimit].map { $0 == primes.count }
        if let valid, !valid {
            throw ValidationError("Unexpected prime count: \(primes.count) below \(upperLimit).")
        }
        if listResults {
            FileHandle.standardError.write(Data((primes.map(String.init).joined(separator: ", ") + "\n").utf8))
        }
        let validation = valid.map { String($0) } ?? "unknown"
        let diagnostic = "Passes: \(passes), Time: \(duration), Avg: \(duration / Double(passes)), Limit: \(upperLimit), Count: \(primes.count), Valid: \(validation), Checksum: \(checksum)\n"
        FileHandle.standardError.write(Data(diagnostic.utf8))
        print("yellowcub_fahlman_striped_UInt8;\(passes);\(duration);1;algorithm=base,faithful=yes,bits=1")
    }
}

// DIAGNOSTIC: phase profile and PRIMES_TEST mode.
struct PassProfile {
    var setup: UInt64 = 0
    var dense: UInt64 = 0
    var sparse: UInt64 = 0
    var runTotal: UInt64 = 0
    var checksum: UInt64 = 0
}

// One profiled pass. The sieve is released when this function returns; deinit
// adds its own duration to PrimeSieve.destroyNanoseconds.
@inline(never)
func profiledPass(limit: Int, offset: Int) -> PassProfile {
    var result = PassProfile()
    var setup: UInt64 = 0
    let sieve = PrimeSieve(limit: limit, setupNanoseconds: &setup)
    let r0 = PrimeSieve.nowNanoseconds()
    let phases = sieve.runSieveProfiled()
    let r1 = PrimeSieve.nowNanoseconds()
    result.setup = setup
    result.dense = phases.dense
    result.sparse = phases.sparse
    result.runTotal = r1 &- r0
    result.checksum = sieve.withStorage { observe($0, at: offset) }
    return result
}

func runPhaseProfile() {
    let limit = 1_000_000
    let passes = 20_000
    let byteCount = PrimeSieve.storageLayout(for: limit).byteCount
    var total = PassProfile()
    PrimeSieve.destroyNanoseconds = 0
    PrimeSieve.profileDestroy = true
    for pass in 0..<passes {
        let offset = byteCount == 0 ? 0 : pass % byteCount
        let one = profiledPass(limit: limit, offset: offset)
        total.setup &+= one.setup
        total.dense &+= one.dense
        total.sparse &+= one.sparse
        total.runTotal &+= one.runTotal
        total.checksum &+= one.checksum
    }
    PrimeSieve.profileDestroy = false
    let destroy = PrimeSieve.destroyNanoseconds
    let n = Double(passes)
    let scan = Double(total.runTotal) - Double(total.dense) - Double(total.sparse)
    let rows: [(String, Double)] = [
        ("setup", Double(total.setup) / n),
        ("dense", Double(total.dense) / n),
        ("sparse", Double(total.sparse) / n),
        ("scan", scan / n),
        ("destroy", Double(destroy) / n),
        ("run_total", Double(total.runTotal) / n),
    ]
    for (phase, nanoseconds) in rows {
        print("yellowcub_fahlman_striped_UInt8;profile;\(phase);\(nanoseconds)")
    }
    FileHandle.standardError.write(Data("Profile passes: \(passes), Checksum: \(total.checksum)\n".utf8))
}

func runPrimesTest() -> Never {
    let limit = 1_000_000
    let expected = 78_498
    let sieve = PrimeSieve(limit: limit)
    sieve.runSieve()
    let count = sieve.primes().count
    // Also check the profiled marking path, which the profile relies on.
    var setup: UInt64 = 0
    let profiled = PrimeSieve(limit: limit, setupNanoseconds: &setup)
    _ = profiled.runSieveProfiled()
    let profiledCount = profiled.primes().count
    let ok = count == expected && profiledCount == expected
    print("size \(limit) -> \(count) primes (expected \(expected)) \(ok ? 1 : 0)")
    exit(ok ? 0 : 1)
}

if let mode = ProcessInfo.processInfo.environment["PRIMES_TEST"], mode != "0" {
    runPrimesTest()
}

runPhaseProfile()
PrimeSieveSwift.main()
