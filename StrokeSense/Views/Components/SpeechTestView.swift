import SwiftUI

/// Records the stroke-scale phrase once. Shared by the baseline and check flows.
struct SpeechTestView<Next: View>: View {
    let context: ArmRecordingLog.Context
    let tint: Color
    let onComplete: (SpeechMetrics) -> Void
    @ViewBuilder let next: () -> Next

    @State private var speechService = SpeechRecognitionService()
    @State private var recorded = false
    @State private var retryMessage: String?
    @State private var audioURL: URL?
    @AppStorage("participant") private var participant = ""
    @State private var label: SpeechRecordingLog.Label = .normal

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: speechService.isListening ? "waveform.circle.fill" : "waveform")
                .font(.system(size: 64))
                .foregroundStyle(recorded ? .green : tint)
                .symbolEffect(.variableColor.iterative, isActive: speechService.isListening)

            Text("Say this phrase aloud, the way you normally talk:")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Text("\"\(SpeechRecognitionService.samplePhrase)\"")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if !speechService.transcription.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You said:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(speechService.transcription)
                        .font(.body)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }

            if let error = speechService.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            if let retryMessage {
                Label(retryMessage, systemImage: "arrow.counterclockwise.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
            }

            if recorded {
                Label("Speech recorded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            Spacer()

            if DevFlags.dataCollection && !recorded && !speechService.isListening {
                dataCollectionControls
            }

            if !recorded {
                Button {
                    if speechService.isListening {
                        Task { await finish() }
                    } else {
                        start()
                    }
                } label: {
                    Text(speechService.isProcessing ? "Processing…" : speechService.isListening ? "Stop" : "Record")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(speechService.isProcessing)

                // Not being able to say the phrase is itself a warning sign, so
                // a check must never loop on "try again". (A baseline must succeed.)
                if context == .check && retryMessage != nil && !speechService.isListening {
                    Button("I can't say it clearly: continue") {
                        onComplete(.unrecognized)
                        recorded = true
                    }
                    .buttonStyle(.bordered)
                    .tint(tint)
                }
            } else {
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
        .onDisappear { speechService.cancel() }
    }

    /// Tags each recording for training data (DevFlags.dataCollection).
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
                Text("Normal speech").tag(SpeechRecordingLog.Label.normal)
                Text("Simulated slurred").tag(SpeechRecordingLog.Label.slurred)
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var currentLabel: SpeechRecordingLog.Label? {
        DevFlags.dataCollection ? label : nil
    }

    private func start() {
        retryMessage = nil
        guard let url = SpeechRecordingLog.newAudioURL(context: context, label: currentLabel, participant: participant) else { return }
        audioURL = url
        speechService.startListening(savingTo: url)
    }

    private func finish() async {
        let metrics = await speechService.stopListening()
        if let audioURL {
            SpeechRecordingLog.save(metrics, audioURL: audioURL, context: context,
                                    label: currentLabel, participant: participant)
        }
        // Never move on with speech that can't be measured: a missing baseline
        // would silently disable the comparison.
        guard let metrics, metrics.isComplete else {
            retryMessage = "Couldn't hear the phrase clearly enough to measure. Please try again."
            return
        }
        onComplete(metrics)
        recorded = true
    }
}
