import SwiftUI

struct BaselineArmsView: View {
    @State private var recorded = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.arms.open")
                .font(.system(size: 64))
                .foregroundStyle(recorded ? .green : .blue)

            Text("Arms Baseline")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Hold both arms straight out in front of you for a few seconds. We'll measure your arm steadiness.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if recorded {
                Label("Arms baseline recorded", systemImage: "checkmark.circle.fill")
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
                    BaselineSpeechView()
                } label: {
                    Text("Next: Speech")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .navigationTitle("Step 2 of 3")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BaselineArmsView()
    }
}
