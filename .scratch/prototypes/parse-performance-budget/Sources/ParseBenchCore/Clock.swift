import Darwin
import Foundation

/// Wall-clock seconds spent in `body`.
public func seconds(_ body: () -> Void) -> Double {
  let start = DispatchTime.now().uptimeNanoseconds
  body()
  return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
}

/// Peak resident bytes for the process so far.
///
/// `ru_maxrss` is a high-water mark, so a run reports the worst moment it reached, not the moment
/// it was asked - which also means that when two strategies are timed in one process, the second
/// row's peak carries the first row's. Read the first row for a clean number.
public func peakResidentBytes() -> Int {
  var usage = rusage()
  getrusage(RUSAGE_SELF, &usage)
  return Int(usage.ru_maxrss)
}
