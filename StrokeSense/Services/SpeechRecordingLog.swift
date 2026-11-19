import Foundation

/// Speech recordings live in Documents/SpeechRecordings: the audio (.wav)
/// written by SpeechRecognitionService plus a .json with the label and
/// measurements, for training the speech classifier (training/speech_classifier).
/// Visible in the Files app under On My iPhone › StrokeSense.
enum SpeechRecordingLog {
    /// Training label chosen in data-collection mode.
    enum Label: String, Codable, CaseIterable {
        case normal, slurred
    }

    private struct Entry: Codable {
        let recordedAt: Date
        let source: String
        let context: ArmRecordingLog.Context
        let label: Label?
        let participant: String?
        let phrase: String
        let metrics: SpeechMetrics?
    }

    static var folder: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SpeechRecordings", isDirectory: true)
    }

    /// Where to write the next recording's audio.
    static func newAudioURL(context: ArmRecordingLog.Context, label: Label?, participant: String?) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let tag = [participant.flatMap { $0.isEmpty ? nil : $0 }, label?.rawValue].compactMap { $0 }.map { "-\($0)" }.joined()
        return folder?.appendingPathComponent("\(formatter.string(from: Date()))-\(context.rawValue)\(tag).wav")
    }

    /// Writes the .json next to the audio file.
    static func save(_ metrics: SpeechMetrics?, audioURL: URL, context: ArmRecordingLog.Context,
                     label: Label?, participant: String?) {
        let entry = Entry(
            recordedAt: Date(),
            source: "app",
            context: context,
            label: label,
            participant: participant.flatMap { $0.isEmpty ? nil : $0 },
            phrase: SpeechRecognitionService.samplePhrase,
            metrics: metrics
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(entry).write(to: audioURL.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
        } catch {
            print("[SpeechRecordingLog] Failed to save: \(error)")
        }
    }
}
