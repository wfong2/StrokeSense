import SwiftUI

struct BaselineFaceView: View {
    @Environment(BaselineManager.self) private var baselineManager
    @State private var faceService = FaceDetectionService()
    @State private var recorded = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Look straight at the camera and smile naturally. We'll capture your facial symmetry as a reference.")
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
                Label("Face baseline recorded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            Spacer()

            if !recorded {
                Button {
                    Task {
                        if let metrics = await faceService.captureSnapshotWithML() {
                            baselineManager.stagedFaceMetrics = metrics
                            recorded = true
                            faceService.stopSession()
                        }
                    }
                } label: {
                    Text("Record")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!faceService.isFaceDetected)
            } else {
                NavigationLink {
                    if DevFlags.faceOnly {
                        BaselineCompleteView()
                    } else {
                        BaselineArmsView()
                    }
                } label: {
                    Text(DevFlags.faceOnly ? "Next: Finish" : "Next: Arms")
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
        .onAppear { faceService.startSession() }
        .onDisappear { faceService.stopSession() }
    }
}

#Preview {
    NavigationStack {
        BaselineFaceView()
            .environment(BaselineManager())
    }
}
