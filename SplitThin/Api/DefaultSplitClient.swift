import Foundation

final class DefaultSplitClient: SplitClient {

    let target: Target
    private var isDestroyed = false

    init(target: Target) {
        self.target = target
    }

    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true
    }
}
