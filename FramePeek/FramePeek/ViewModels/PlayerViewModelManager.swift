import Foundation
import SwiftUI

/// Shared manager to track the active ViewModel for the video player window
@MainActor
final class PlayerViewModelManager: ObservableObject {
    static let shared = PlayerViewModelManager()
    
    @Published var activeViewModel: FramePeekViewModel?
    
    private init() {}
    
    func setActiveViewModel(_ viewModel: FramePeekViewModel?) {
        activeViewModel = viewModel
    }
}


