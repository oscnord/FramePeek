import Foundation
import FramePeekCore

extension FramePeekViewModel {

    /// Starts container structure analysis for the given file
    func startContainerAnalysis(url: URL) {
        // Cancel existing task if any
        containerTask?.cancel()

        isAnalyzingContainer = true

        containerTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = await ContainerParser.parse(url: url)

            await MainActor.run {
                guard let self else { return }
                self.containerAnalysis = result
                self.isAnalyzingContainer = false
            }
        }
    }
}
