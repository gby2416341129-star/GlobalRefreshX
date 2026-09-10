import Foundation

/// Small single-owner scheduler for replaceable delayed work.
/// A slot can have at most one live task; rescheduling the same slot cancels the previous task.
/// This prevents stale callbacks from mutating UI/lifecycle state after a newer intent has won.
final class DelayedTaskScheduler<Slot: Hashable> {
    private var workItems: [Slot: DispatchWorkItem] = [:]

    func schedule(
        _ slot: Slot,
        after delay: TimeInterval,
        on queue: DispatchQueue = .main,
        action: @escaping () -> Void
    ) {
        cancel(slot)

        var item: DispatchWorkItem!
        item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.workItems[slot] === item else { return }
            self.workItems[slot] = nil
            guard !item.isCancelled else { return }
            action()
        }
        workItems[slot] = item
        queue.asyncAfter(deadline: .now() + max(0, delay), execute: item)
    }

    func cancel(_ slot: Slot) {
        workItems.removeValue(forKey: slot)?.cancel()
    }

    func cancelAll() {
        let items = Array(workItems.values)
        workItems.removeAll()
        items.forEach { $0.cancel() }
    }

    func isScheduled(_ slot: Slot) -> Bool {
        workItems[slot] != nil
    }
}
