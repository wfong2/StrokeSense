import Foundation

enum ArmSide: String {
    case left, right
}

/// Saves every arm hold as JSON in Documents/ArmRecordings so the per-frame
/// time series can be collected as training data for the arm-drift classifier.
/// Files are visible in the Files app under On My iPhone › StrokeSense.
enum ArmRecordingLog {
    enum Context: String, Codable {
        case baseline, check
    }

    /// Training label chosen in data-collection mode.
    enum Label: String, Codable, CaseIterable {
        case normal, drift
    }

    private struct Entry: Codable {
        let recordedAt: Date
        let source: String
        let context: Context
        let side: String
        /// Nil outside data-collection mode; unlabelled files are not used for training.
        let label: Label?
        let participant: String?
        let complete: Bool
        let grip: String?
        let gripUsable: Bool
        let meanElevation: Double?
        let drift: Double?
        let pronation: Double?
        let shake: Double?
        let samples: [ArmSample]
    }

    static func save(_ recording: ArmRecording, side: ArmSide, context: Context,
                     label: Label? = nil, participant: String? = nil) {
        let entry = Entry(
            recordedAt: Date(),
            source: "app",
            context: context,
            side: side.rawValue,
            label: label,
            participant: participant.flatMap { $0.isEmpty ? nil : $0 },
            complete: recording.isComplete,
            grip: recording.gripName,
            gripUsable: recording.isGripUsable,
            meanElevation: recording.meanElevation,
            drift: recording.drift,
            pronation: recording.pronation,
            shake: recording.shake,
            samples: recording.samples
        )

        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("ArmRecordings", isDirectory: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let tag = [entry.participant, label?.rawValue].compactMap { $0 }.map { "-\($0)" }.joined()
        let name = "\(formatter.string(from: entry.recordedAt))-\(context.rawValue)-\(side.rawValue)\(tag).json"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoder.encode(entry).write(to: folder.appendingPathComponent(name), options: .atomic)
        } catch {
            print("[ArmRecordingLog] Failed to save \(name): \(error)")
        }
    }
}
