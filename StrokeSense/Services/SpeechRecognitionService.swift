import AVFoundation
@preconcurrency import Speech

@Observable
final class SpeechRecognitionService: @unchecked Sendable {
    static let samplePhrase = "The quick brown fox jumps over the lazy dog."

    private(set) var isListening = false
    private(set) var transcription = ""
    var errorMessage: String?

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recordingStartTime: Date?
    private var latestResult: SFSpeechRecognitionResult?

    #if targetEnvironment(simulator)
    private let isSimulator = true
    #else
    private let isSimulator = false
    #endif

    func startListening() {
        guard !isListening else { return }
        errorMessage = nil

        guard !isSimulator else {
            isListening = true
            transcription = Self.samplePhrase
            return
        }

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

    func stopListening() -> SpeechMetrics? {
        guard isListening else { return nil }

        guard !isSimulator else {
            isListening = false
            return SpeechMetrics(clarity: 0.92, wordsPerMinute: 130.0, samplePhrase: Self.samplePhrase)
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        isListening = false

        let metrics = computeMetrics()

        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        latestResult = nil

        return metrics
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
        self.recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    self.transcription = result.bestTranscription.formattedString
                    self.latestResult = result
                }
            }
            if error != nil {
                DispatchQueue.main.async {
                    self.audioEngine.stop()
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                    self.isListening = false
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            recordingStartTime = Date()
            transcription = ""
        } catch {
            errorMessage = "Failed to start audio engine."
        }
    }

    private func computeMetrics() -> SpeechMetrics? {
        guard let startTime = recordingStartTime else { return nil }

        let duration = Date().timeIntervalSince(startTime)
        guard duration > 0 else { return nil }

        let text = transcription
        let spokenWords = text.lowercased().split(separator: " ").map(String.init)
        guard !spokenWords.isEmpty else { return nil }

        let durationMinutes = duration / 60.0
        let wpm = Double(spokenWords.count) / durationMinutes

        // Use real segment confidence if available (from a final result),
        // otherwise fall back to word-overlap similarity against the target phrase.
        var clarity: Double
        if let result = latestResult, result.isFinal {
            let segments = result.bestTranscription.segments
            let confidences = segments.map { Double($0.confidence) }
            let nonZero = confidences.filter { $0 > 0 }
            if !nonZero.isEmpty {
                clarity = min(max(nonZero.reduce(0, +) / Double(nonZero.count), 0), 1)
            } else {
                clarity = wordOverlapClarity(spokenWords: spokenWords)
            }
        } else {
            clarity = wordOverlapClarity(spokenWords: spokenWords)
        }

        return SpeechMetrics(clarity: clarity, wordsPerMinute: wpm, samplePhrase: Self.samplePhrase)
    }

    private func wordOverlapClarity(spokenWords: [String]) -> Double {
        let targetWords = Self.samplePhrase.lowercased()
            .filter { $0.isLetter || $0.isWhitespace }
            .split(separator: " ")
            .map(String.init)

        guard !targetWords.isEmpty else { return 0 }

        var remaining = spokenWords
        var matched = 0
        for target in targetWords {
            if let idx = remaining.firstIndex(of: target) {
                matched += 1
                remaining.remove(at: idx)
            }
        }

        let matchRatio = Double(matched) / Double(targetWords.count)
        // Penalize extra words (speaking much more than the target phrase)
        let extraRatio = Double(max(spokenWords.count - targetWords.count, 0)) / Double(targetWords.count)
        let penalty = min(extraRatio * 0.1, 0.3)

        return min(max(matchRatio - penalty, 0), 1)
    }
}
