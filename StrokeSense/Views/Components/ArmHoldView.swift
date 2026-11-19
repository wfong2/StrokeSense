import AVFoundation
import SwiftUI
import UIKit

/// Guides one arm-hold test per arm using the phone's motion sensors.
/// The user can't see the screen with the arm stretched out, so every step
/// is also spoken aloud and marked with a vibration.
struct ArmHoldView<Next: View>: View {
    let context: ArmRecordingLog.Context
    let tint: Color
    let onComplete: (ArmMetrics) -> Void
    @ViewBuilder let next: () -> Next

    private enum Phase: Equatable {
        case ready(ArmSide)
        case getReady(ArmSide, Int)
        case recording(ArmSide, Int)
        case done
    }

    @State private var motion = ArmMotionService()
    @State private var phase: Phase = .ready(.right)
    @State private var rightRecording: ArmRecording?
    @State private var task: Task<Void, Never>?
    @State private var speaker = AVSpeechSynthesizer()
    @AppStorage("participant") private var participant = ""
    @State private var label: ArmRecordingLog.Label = .normal
    /// Set when the last hold didn't record enough to measure.
    @State private var retryMessage: String?

    private let getReadySeconds = 3
    // First second is skipped as settling time, leaving ~7 s to see drift.
    private let recordingSeconds = 8

    var body: some View {
        VStack(spacing: 24) {
            switch phase {
            case .ready(let side):
                instructions(for: side)
                if let retryMessage {
                    Label(retryMessage, systemImage: "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                }
                Spacer()
                if DevFlags.dataCollection {
                    dataCollectionControls
                }
                flatIndicator
                Button {
                    begin(side)
                } label: {
                    Text("Start \(side.rawValue.capitalized) Arm")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)

            case .getReady(let side, let seconds):
                Spacer()
                Text("Raise your \(side.rawValue) arm")
                    .font(.title2.bold())
                Text("\(seconds)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                Spacer()

            case .recording(_, let seconds):
                Spacer()
                Label("Hold still", systemImage: "record.circle")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
                Text("\(seconds)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                Spacer()

            case .done:
                Spacer()
                Label("Both arms recorded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Spacer()
                NavigationLink {
                    next()
                } label: {
                    Text("Next")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .padding()
        .onAppear { motion.start() }
        .onDisappear {
            task?.cancel()
            motion.stop()
            speaker.stopSpeaking(at: .immediate)
        }
    }

    private func instructions(for side: ArmSide) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(side.rawValue.capitalized) arm")
                .font(.largeTitle.bold())
            Label("Hold the phone upright in your \(side.rawValue) hand, screen facing you.", systemImage: "iphone")
            Label("Tap Start, then stretch that arm straight out in front of you at shoulder height. Keep your wrist straight.", systemImage: "arrow.right")
            Label("Close your eyes and hold still until the phone says \"Done\".", systemImage: "eye.slash")
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Tags each hold for training data (DevFlags.dataCollection).
    private var dataCollectionControls: some View {
        VStack(spacing: 8) {
            Text("Data collection")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("Participant code (e.g. initials)", text: $participant)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Picker("Label", selection: $label) {
                Text("Normal hold").tag(ArmRecordingLog.Label.normal)
                Text("Simulated drift").tag(ArmRecordingLog.Label.drift)
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var flatIndicator: some View {
        Label(motion.isGripUsable ? "Phone grip OK" : "Don't turn the phone on its side",
              systemImage: motion.isGripUsable ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(motion.isGripUsable ? .green : .orange)
            .font(.headline)
    }

    private func begin(_ side: ArmSide) {
        task = Task { @MainActor in
            speak("Stretch your \(side.rawValue) arm straight out in front of you.")
            for s in stride(from: getReadySeconds, to: 0, by: -1) {
                phase = .getReady(side, s)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }

            motion.startRecording()
            buzz(.success)
            speak("Close your eyes and hold still.")
            for s in stride(from: recordingSeconds, to: 0, by: -1) {
                phase = .recording(side, s)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }

            let recording = motion.finishRecording()
            if DevFlags.dataCollection {
                ArmRecordingLog.save(recording, side: side, context: context, label: label, participant: participant)
            } else {
                ArmRecordingLog.save(recording, side: side, context: context)
            }

            // Never move on with an arm that can't be measured: a missing
            // baseline arm would silently disable the arm comparison.
            guard recording.isComplete else {
                buzz(.error)
                retryMessage = recording.samples.count < 20
                    ? "That hold didn't record. Please try the \(side.rawValue) arm again."
                    : "Keep the phone upright, not on its side. Please try the \(side.rawValue) arm again."
                speak("That didn't record properly. Lower your arm and let's try the \(side.rawValue) arm again.")
                phase = .ready(side)
                return
            }
            retryMessage = nil
            buzz(.success)

            if side == .right {
                rightRecording = recording
                speak("Done. Lower your arm and switch the phone to your left hand.")
                phase = .ready(.left)
            } else {
                speak("Done. You can lower your arm.")
                onComplete(ArmMetrics(left: recording, right: rightRecording))
                motion.stop()
                phase = .done
            }
        }
    }

    private func speak(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        speaker.speak(AVSpeechUtterance(string: text))
    }

    private func buzz(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
