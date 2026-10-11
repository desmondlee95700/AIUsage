import Foundation

/// Runs blocking work (subprocesses, `ps`/`lsof`, app bundle walks) on a global dispatch queue and
/// resumes the caller with its result. Keeps that work off the main thread and off Swift's cooperative
/// thread pool, which expects tasks to suspend rather than block.
func runBlocking<T>(qos: DispatchQoS.QoSClass = .userInitiated, _ work: @escaping () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qos).async {
            continuation.resume(returning: work())
        }
    }
}
