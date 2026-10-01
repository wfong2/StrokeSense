import SwiftUI

struct CheckArmsView: View {
    @Environment(BaselineManager.self) private var baselineManager
    @State private var poseService = PoseDetectionService()
    @State private var recorded = false
    @State private var countdown: Int?
    @State private var countdownTimer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            Text("Stand back so your upper body is visible. Hold both arms straight out — we'll auto-capture after 3 seconds.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            CameraPreviewView(session: poseService.captureSession)
                .frame(height: 400)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(poseService.isBodyDetected ? Color.green : Color.gray, lineWidth: 3)
                )
                .overlay {
                    if let countdown, !recorded {
                        Text("\(countdown)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                }
                .padding(.horizontal)

            if poseService.isBodyDetected && !recorded {
                Label("Body detected — hold still", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            if recorded {
                Label("Arms check recorded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            Spacer()

            if recorded {
                NavigationLink {
                    CheckSpeechView()
                } label: {
                    Text("Next: Speech")
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
        .navigationTitle("Step 2 of 3")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { poseService.startSession() }
        .onDisappear {
            poseService.stopSession()
            cancelCountdown()
        }
        .onChange(of: poseService.isBodyDetected) { _, detected in
            guard !recorded else { return }
            if detected {
                startCountdown()
            } else {
                cancelCountdown()
            }
        }
    }

    private func startCountdown() {
        countdown = 3
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard let current = countdown else { return }
            if current <= 1 {
                cancelCountdown()
                if let metrics = poseService.captureSnapshot() {
                    baselineManager.stagedArmMetrics = metrics
                    recorded = true
                    poseService.stopSession()
                }
            } else {
                countdown = current - 1
            }
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = nil
    }
}

#Preview {
    NavigationStack {
        CheckArmsView()
            .environment(BaselineManager())
    }
}
