import SwiftUI

struct CheckFaceView: View {
    @Environment(BaselineManager.self) private var baselineManager
    @State private var faceService = FaceDetectionService()
    @State private var recorded = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Look straight at the camera and smile naturally. We'll compare your facial symmetry against your baseline.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            CameraPreviewView(session: faceService.captureSession)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(faceService.isFaceDetected ? Color.green : Color.gray, lineWidth: 3)
                )
                .padding(.horizontal)

            if faceService.isFaceDetected && !recorded {
                Label("Face detected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            if recorded {
                Label("Face check recorded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            Spacer()

            if !recorded {
                Button {
                    if let metrics = faceService.captureSnapshot() {
                        baselineManager.stagedFaceMetrics = metrics
                        recorded = true
                        faceService.stopSession()
                    }
                } label: {
                    Text("Record")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!faceService.isFaceDetected)
            } else {
                NavigationLink {
                    CheckArmsView()
                } label: {
                    Text("Next: Arms")
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
        .navigationTitle("Step 1 of 3")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { faceService.startSession() }
        .onDisappear { faceService.stopSession() }
    }
}

#Preview {
    NavigationStack {
        CheckFaceView()
            .environment(BaselineManager())
    }
}
