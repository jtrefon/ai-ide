import Foundation

enum AppConstantsTime {
    static let errorAutoDismissDelay: TimeInterval = 5.0
    static let searchDebounceDelay: TimeInterval = 0.25
    static let quickSearchDebounceNanoseconds: UInt64 = 150_000_000
    static let processTerminationTimeout: TimeInterval = 0.5
}
