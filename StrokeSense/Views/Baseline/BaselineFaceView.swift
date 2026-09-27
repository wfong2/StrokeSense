import SwiftUI

struct BaselineFaceView: View {
    @State private var recorded = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "face.smiling")
                .font(.system(size: 64))
                .foregroundStyle(recorded ? .green : .blue)

            Text("Face Baseline")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Look straight at the camera and smile naturally. We'll capture your facial symmetry as a reference.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if recorded {
                Label("Face baseline recorded", systemImage: "checkmark.circle.fill")
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
                    BaselineArmsView()
                } label: {
                    Text("Next: Arms")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .navigationTitle("Step 1 of 3")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BaselineFaceView()
    }
}
