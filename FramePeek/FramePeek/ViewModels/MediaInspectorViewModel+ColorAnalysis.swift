import Foundation
import AVFoundation
import FramePeekCore

extension FramePeekViewModel {
    /// Starts color analysis (manual trigger)
    func startColorAnalysis(asset: AVAsset) {
        guard let url = currentVideoURL else { return }

        colorAnalysisTask?.cancel()

        isAnalyzingColor = true
        colorSamples = []
        professionalColorAnalysis = []
        colorAnalysisProgress = 0

        let assetForColor = AVURLAsset(url: url)

        // Load settings from UserDefaults with proper defaults
        // Note: bool(forKey:) returns false for unset keys, so we need object(forKey:) for defaults
        let sampleInterval = UserDefaults.standard.double(forKey: "colorAnalysisSampleInterval")
        let maxSamples = UserDefaults.standard.integer(forKey: "colorAnalysisMaxSamples")
        
        // For boolean settings, use object(forKey:) to detect if value was ever set
        // Default to true if never set (matching @AppStorage defaults in settings)
        let generateWaveform = UserDefaults.standard.object(forKey: "generateWaveformData") as? Bool ?? true
        let generateVectorscope = UserDefaults.standard.object(forKey: "generateVectorscopeData") as? Bool ?? true
        
        let waveformScaleRaw = UserDefaults.standard.string(forKey: "waveformScale") ?? WaveformScale.percentage.rawValue
        let waveformScale = WaveformScale(rawValue: waveformScaleRaw) ?? .percentage

        // Use defaults if not set
        let effectiveInterval = sampleInterval > 0 ? sampleInterval : 1.0
        let effectiveMaxSamples = maxSamples > 0 ? maxSamples : 1000
        
        // Create config based on detected HDR type
        let config = ColorAnalysisConfig(
            hdrContentType: hdrContentType,
            waveformScale: waveformScale,
            generateWaveform: generateWaveform,
            generateVectorscope: generateVectorscope,
            waveformResolution: 256,
            vectorscopeResolution: 128
        )

        colorAnalysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            for await update in analyzeColorProfessional(
                asset: assetForColor,
                config: config,
                sampleInterval: effectiveInterval,
                maxSamples: effectiveMaxSamples
            ) {
                if Task.isCancelled { break }

                await MainActor.run {
                    if !Task.isCancelled {
                        self.professionalColorAnalysis = update.samples
                        self.colorAnalysisProgress = update.progress
                        
                        // Also update legacy colorSamples for backward compatibility
                        self.colorSamples = convertToLegacyColorSamples(update.samples)
                        
                        if update.isFinished {
                            self.isAnalyzingColor = false
                        }
                    }
                }
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.isAnalyzingColor = false
                }
                self.colorAnalysisTask = nil
            }
        }
    }

    /// Cancels color analysis
    func cancelColorAnalysis() {
        colorAnalysisTask?.cancel()
        colorAnalysisTask = nil
        isAnalyzingColor = false
    }
    
    /// Detects HDR content type from video metadata
    func detectHDRType() async {
        guard let url = currentVideoURL else { return }
        
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
        
        // Get transfer function and color primaries
        let formatDescriptions = try? await track.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions?.first,
              let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any] else {
            return
        }
        
        let transferFunction = extDict[kCMFormatDescriptionExtension_TransferFunction] as? String
        let colorPrimaries = extDict[kCMFormatDescriptionExtension_ColorPrimaries] as? String
        
        // Check for Dolby Vision
        var hasDolbyVision = false
        if let atoms = extDict[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [CFString: Any] {
            hasDolbyVision = atoms["dvcC" as CFString] != nil || atoms["dvvC" as CFString] != nil
            
            // Try to parse Dolby Vision config
            if hasDolbyVision {
                if let config = await extractDolbyVisionConfig(from: track) {
                    await MainActor.run {
                        self.dolbyVisionConfig = config
                    }
                }
            }
        }
        
        let detectedType = detectHDRContentType(
            transferFunction: transferFunction,
            colorPrimaries: colorPrimaries,
            hasDolbyVision: hasDolbyVision
        )
        
        await MainActor.run {
            self.hdrContentType = detectedType
        }
    }
    
    /// Gets aggregated color statistics from professional analysis
    var aggregatedColorStats: AggregatedColorStats? {
        guard !professionalColorAnalysis.isEmpty else { return nil }
        
        let luminances = professionalColorAnalysis.map { $0.luminance }
        let saturations = professionalColorAnalysis.map { $0.saturation }
        let temperatures = professionalColorAnalysis.compactMap { $0.colorTemperature }
        
        return AggregatedColorStats(
            luminanceMin: luminances.map { $0.min }.min() ?? 0,
            luminanceMax: luminances.map { $0.max }.max() ?? 0,
            luminanceAvg: luminances.map { $0.average }.reduce(0, +) / Double(luminances.count),
            saturationAvg: saturations.reduce(0, +) / Double(saturations.count),
            cctAvg: temperatures.isEmpty ? nil : temperatures.map { $0.cct }.reduce(0, +) / Double(temperatures.count),
            cctMin: temperatures.map { $0.cct }.min(),
            cctMax: temperatures.map { $0.cct }.max()
        )
    }
    
    /// Gets the latest waveform data for display
    var latestWaveformData: WaveformData? {
        professionalColorAnalysis.last?.waveformData
    }
    
    /// Gets the latest vectorscope data for display
    var latestVectorscopeData: VectorscopeData? {
        professionalColorAnalysis.last?.vectorscopeData
    }
    
    /// Gets waveform data at a specific time
    func waveformDataAtTime(_ time: Double) -> WaveformData? {
        guard let idx = binarySearchClosest(
            in: professionalColorAnalysis,
            targetTime: time,
            timeKeyPath: \.time
        ) else { return nil }
        return professionalColorAnalysis[idx].waveformData
    }
    
    /// Gets vectorscope data at a specific time
    func vectorscopeDataAtTime(_ time: Double) -> VectorscopeData? {
        guard let idx = binarySearchClosest(
            in: professionalColorAnalysis,
            targetTime: time,
            timeKeyPath: \.time
        ) else { return nil }
        return professionalColorAnalysis[idx].vectorscopeData
    }
    
    /// Gets frame analysis at a specific time
    func frameAnalysisAtTime(_ time: Double) -> FrameColorAnalysis? {
        guard let idx = binarySearchClosest(
            in: professionalColorAnalysis,
            targetTime: time,
            timeKeyPath: \.time
        ) else { return nil }
        return professionalColorAnalysis[idx]
    }
}
