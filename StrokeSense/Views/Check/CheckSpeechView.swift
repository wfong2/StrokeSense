import SwiftUI

struct CheckSpeechView: View {
    @Environment(BaselineManager.self) private var baselineManager
    @State private var speechService = SpeechRecognitionService()
    @State private var recorded = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: speechService.isListening ? "waveform.circle.fill" : "waveform")
                .font(.system(size: 64))
                .foregroundStyle(recorded ? .green : .red)
                .symbolEffect(.variableColor.iterative, isActive: speechService.isListening)

            Text("Speech Check")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Read the following phrase aloud clearly to compare against your baseline:")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Text("\"\(SpeechRecognitionService.samplePhrase)\"")
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if !speechService.transcription.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You said:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(speechService.transcription)
                        .font(.body)
                        .foregroundStyle(.primary)
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

            if recorded {
                Label("Speech check recorded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            Spacer()

            if !recorded {
                Button {
                    if speechService.isListening {
                        if let metrics = speechService.stopListening() {
                            baselineManager.stagedSpeechMetrics = metrics
                            recorded = true
                        }
                    } else {
                        speechService.startListening()
                    }
                } label: {
                    Text(speechService.isListening ? "Stop Recording" : "Record")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                NavigationLink {
                    CheckResultsView()
                } label: {
                    Text("Next: Results")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .navigationTitle("Step 3 of 3")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if speechService.isListening {
                _ = speechService.stopListening()
            }
        }
    }
}

#Preview {
    NavigationStack {
        CheckSpeechView()
            .environment(BaselineManager())
    }
}
