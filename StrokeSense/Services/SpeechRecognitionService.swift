import AVFoundation
@preconcurrency import Speech

/// Records one spoken phrase, transcribes it on the device, saves the audio,
/// and measures word accuracy, speaking rate, pauses and voice quality.
@Observable
final class SpeechRecognitionService: @unchecked Sendable {
    /// Cincinnati Prehospital Stroke Scale phrase, the one EMS crews use.
    static let samplePhrase = "You can't teach an old dog new tricks."

    private(set) var isListening = false
    private(set) var isProcessing = false
    private(set) var transcription = ""
    var errorMessage: String?

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var latestResult: SFSpeechRecognitionResult?
    private var audioFile: AVAudioFile?
    private var audioURL: URL?

    #if targetEnvironment(simulator)
    private let isSimulator = true
    #else
    private let isSimulator = false
    #endif

    /// Starts listening; audio is also written to `audioURL` (a .wav file).
    func startListening(savingTo audioURL: URL) {
        guard !isListening, !isProcessing else { return }
        errorMessage = nil
        transcription = ""

        guard !isSimulator else {
            isListening = true
            transcription = Self.samplePhrase
            return
        }

        self.audioURL = audioURL
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .authorized:
                    self.requestMicrophoneAndStart()
                case .denied, .restricted:
                    self.errorMessage = "Speech recognition permission denied. Please enable it in Settings."
                case .notDetermined:
                    self.errorMessage = "Speech recognition permission not determined."
                @unknown default:
                    self.errorMessage = "Speech recognition unavailable."
                }
            }
        }
    }

    /// Stops listening, waits briefly for the recognizer's final result, and
    /// returns the measurements. Nil if nothing usable was recognized.
    @MainActor
    func stopListening() async -> SpeechMetrics? {
        guard isListening else { return nil }

        guard !isSimulator else {
            isListening = false
            return SpeechMetrics(samplePhrase: Self.samplePhrase, transcript: Self.samplePhrase,
                                 wordAccuracy: 1.0, speechRate: 3.0, pauseRatio: 0.1)
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        audioFile = nil  // closes the file
        isListening = false
        isProcessing = true
        defer { isProcessing = false }

        // The final result (with word timings and voice analytics) arrives
        // shortly after endAudio(). Measuring a partial result would make the
        // baseline and the check use different data.
        for _ in 0..<40 where latestResult?.isFinal != true {
            try? await Task.sleep(for: .milliseconds(100))
        }

        let metrics = latestResult.flatMap { computeMetrics(from: $0) }
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        latestResult = nil
        return metrics
    }

    /// Stops without measuring (e.g. the user left the screen).
    func cancel() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        audioFile = nil
        isListening = false
    }

    // MARK: - Private

    private func requestMicrophoneAndStart() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.beginRecognition()
                } else {
                    self.errorMessage = "Microphone permission denied. Please enable it in Settings."
                }
            }
        }
    }

    private func beginRecognition() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available on this device."
            return
        }
        // Keep the user's voice on the phone. Without this, iOS may send the
        // audio to Apple's servers for transcription.
        guard speechRecognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device speech recognition isn't supported on this device."
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to configure audio session."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = false
        self.recognitionRequest = request
        latestResult = nil

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            DispatchQueue.main.async {
                self.transcription = result.bestTranscription.formattedString
                self.latestResult = result
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        if let audioURL {
            try? FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            audioFile = try? AVAudioFile(forWriting: audioURL, settings: format.settings)
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            try? self?.audioFile?.write(from: buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = "Failed to start audio engine."
        }
    }

    private func computeMetrics(from result: SFSpeechRecognitionResult) -> SpeechMetrics? {
        let segments = result.bestTranscription.segments.filter { !$0.substring.isEmpty }
        guard let first = segments.first, let last = segments.last else { return nil }

        let words = segments.map { Self.normalize($0.substring) }.filter { !$0.isEmpty }
        let span = last.timestamp + last.duration - first.timestamp
        guard !words.isEmpty, span > 0 else { return nil }

        // Gaps between consecutive words; tiny gaps are normal articulation.
        var gaps = 0.0
        for (a, b) in zip(segments, segments.dropFirst()) {
            let gap = b.timestamp - (a.timestamp + a.duration)
            if gap > 0.15 { gaps += gap }
        }

        let voice = Self.voiceQuality(result.speechRecognitionMetadata?.voiceAnalytics)

        return SpeechMetrics(
            samplePhrase: Self.samplePhrase,
            transcript: result.bestTranscription.formattedString,
            wordAccuracy: Self.wordAccuracy(spoken: words),
            speechRate: Double(words.count) / span,
            pauseRatio: min(gaps / span, 1.0),
            jitter: voice.jitter,
            shimmer: voice.shimmer,
            pitchVariation: voice.pitchVariation,
            audioFileName: audioURL?.lastPathComponent
        )
    }

    /// Lowercase letters only, so "Can't" and "cant" match.
    static func normalize(_ word: String) -> String {
        word.lowercased().filter(\.isLetter)
    }

    /// Fraction of the phrase's words that appear in what was said.
    static func wordAccuracy(spoken: [String]) -> Double {
        let target = samplePhrase.split(separator: " ").map { normalize(String($0)) }.filter { !$0.isEmpty }
        guard !target.isEmpty else { return 0 }
        // The recognizer often writes "can't" as "can", "cannot" or "can not".
        var remaining: [String] = []
        for word in spoken {
            if word == "not", remaining.last == "cant" { continue }
            remaining.append(word == "can" || word == "cannot" ? "cant" : word)
        }
        var matched = 0
        for word in target {
            if let i = remaining.firstIndex(of: word) {
                matched += 1
                remaining.remove(at: i)
            }
        }
        return Double(matched) / Double(target.count)
    }

    /// Means of jitter and shimmer, and spread of pitch, over voiced frames.
    private static func voiceQuality(_ analytics: SFVoiceAnalytics?)
        -> (jitter: Double?, shimmer: Double?, pitchVariation: Double?) {
        guard let analytics else { return (nil, nil, nil) }
        let voicing = analytics.voicing.acousticFeatureValuePerFrame
        func voiced(_ values: [Double]) -> [Double] {
            zip(values, voicing).filter { $0.1 > 0.5 }.map(\.0)
        }
        func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        let pitch = voiced(analytics.pitch.acousticFeatureValuePerFrame)
        let pitchSD = mean(pitch).map { m in (pitch.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(pitch.count)).squareRoot() }
        return (mean(voiced(analytics.jitter.acousticFeatureValuePerFrame)),
                mean(voiced(analytics.shimmer.acousticFeatureValuePerFrame)),
                pitchSD)
    }
}
