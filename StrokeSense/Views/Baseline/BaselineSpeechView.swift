import SwiftUI

struct BaselineSpeechView: View {
    @State private var recorded = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(recorded ? .green : .blue)

            Text("Speech Baseline")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Read the following phrase aloud clearly:\n\n\"The quick brown fox jumps over the lazy dog.\"")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if recorded {
                Label("Speech baseline recorded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            Spacer()

            if !recorded {
                Button {
                    recorded = true
                } label: {
                    Text("Record")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
            } else {
                NavigationLink {
                    BaselineCompleteView()
                } label: {
                    Text("Next: Finish")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .navigationTitle("Step 3 of 3")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BaselineSpeechView()
    }
}
