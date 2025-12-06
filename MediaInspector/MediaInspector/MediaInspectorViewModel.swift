//
//  MediaInspectorViewModel.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import AVFoundation

final class MediaInspectorViewModel: ObservableObject {
    @Published var samples: [BitrateSample] = []
    @Published var extendedInfo: ExtendedVideoInfo?
    @Published var effectiveFPS: Double?
    @Published var minInterval: Double?
    @Published var maxInterval: Double?
    @Published var hoveredSample: BitrateSample?
    @Published var isAnalyzing: Bool = false

    func pickFile() {
        openFileDialog { [weak self] path in
            guard let self, let path else { return }
            self.loadAsset(atPath: path)
        }
    }

    func loadAsset(atPath path: String) {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        
        self.samples = []
        self.effectiveFPS = nil
        self.minInterval = nil
        self.maxInterval = nil
        self.hoveredSample = nil
        self.isAnalyzing = true

        Task { @MainActor in
            self.extendedInfo = await getExtendedInfo(url: url, asset: asset)
        }

        extractFrames(asset: asset) { [weak self] result in
            guard let self else { return }

            self.samples = result.samples
            self.effectiveFPS = result.averageFPS
            self.minInterval = result.minInterval
            self.maxInterval = result.maxInterval
            self.isAnalyzing = false
        }
    }

    func reset() {
        samples = []
        extendedInfo = nil
        effectiveFPS = nil
        minInterval = nil
        maxInterval = nil
        hoveredSample = nil
        isAnalyzing = false
    }
}
