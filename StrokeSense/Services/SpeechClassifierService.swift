import AVFoundation
import CoreML

/// Runs the Core ML slurred-speech classifier (training/speech_classifier) on a
/// saved recording. Returns a dysarthria probability (0.0–1.0), or nil if the
/// model or the audio is unavailable.
///
/// The model includes its own spectrogram front end, so the app only resamples
/// to 16 kHz mono and cuts the same 4 s window as training (centre crop or pad).
final class SpeechClassifierService: @unchecked Sendable {
    static let shared = SpeechClassifierService()

    static let sampleRate = 16_000.0
    static let clipSamples = 64_000

    private let model: MLModel?
    private var cache: [String: Double] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "SpeechClarityClassifier", withExtension: "mlmodelc") else {
            print("[SpeechClassifierService] Model not bundled")
            model = nil
            return
        }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        model = try? MLModel(contentsOf: url, configuration: config)
    }

    var isAvailable: Bool { model != nil }

    /// Probability for a recording in Documents/SpeechRecordings.
    func dysarthriaProbability(audioFileName: String?) -> Double? {
        guard let model, let name = audioFileName,
              let url = SpeechRecordingLog.folder?.appendingPathComponent(name) else { return nil }
        if let cached = cache[name] { return cached }
        guard let samples = Self.loadMono16k(url) else { return nil }
        let clip = Self.fitClip(samples)

        guard let array = try? MLMultiArray(shape: [1, NSNumber(value: Self.clipSamples)], dataType: .float32) else { return nil }
        clip.withUnsafeBufferPointer { src in
            let dst = array.dataPointer.bindMemory(to: Float.self, capacity: Self.clipSamples)
            dst.update(from: src.baseAddress!, count: Self.clipSamples)
        }
        guard let input = try? MLDictionaryFeatureProvider(dictionary: ["audio": array]),
              let output = try? model.prediction(from: input),
              let logit = output.featureValue(for: "dysarthriaLogit")?.multiArrayValue?[0].doubleValue else { return nil }
        let p = 1.0 / (1.0 + exp(-logit))
        cache[name] = p
        return p
    }

    /// Centre-crop or zero-pad to exactly 4 s (same rule as 01_prepare_dataset.py).
    static func fitClip(_ samples: [Float]) -> [Float] {
        if samples.count >= clipSamples {
            let start = (samples.count - clipSamples) / 2
            return Array(samples[start..<start + clipSamples])
        }
        let pad = clipSamples - samples.count
        return [Float](repeating: 0, count: pad / 2) + samples + [Float](repeating: 0, count: pad - pad / 2)
    }

    /// Reads a recording and converts it to 16 kHz mono floats.
    static func loadMono16k(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: input)) != nil else { return nil }

        let ratio = sampleRate / file.processingFormat.sampleRate
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let data = output.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
