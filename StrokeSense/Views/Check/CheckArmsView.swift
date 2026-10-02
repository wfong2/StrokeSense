import SwiftUI

private enum ArmCheckPhase {
    case rightArm   // phone in left hand, extend right arm
    case transition // brief pause to switch hands
    case leftArm    // phone in right hand, extend left arm
    case done
}

struct CheckArmsView: View {
    @Environment(BaselineManager.self) private var baselineManager
    @State private var poseService = PoseDetectionService()
    @State private var phase: ArmCheckPhase = .rightArm
    @State private var recording = false
    @State private var secondsRemaining: Int = 5
    @State private var recordingTimer: Timer?

    @State private var rightArmResult: (angle: Double, steadiness: Double)?
    @State private var leftArmResult: (angle: Double, steadiness: Double)?

    private let recordingDuration = 5

    private var instructionText: String {
        switch phase {
        case .rightArm:
            return "Hold your phone in your left hand. Extend your right arm straight out to the side."
        case .transition:
            return "Right arm recorded. Now switch your phone to your right hand."
        case .leftArm:
            return "Hold your phone in your right hand. Extend your left arm straight out to the side."
        case .done:
            return "Both arms recorded."
        }
    }

    private var borderColor: Color {
        if phase == .done { return .green }
        if recording { return .green }
        if poseService.isBodyDetected { return .orange }
        return .gray
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(instructionText)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if phase != .transition {
                CameraPreviewView(session: poseService.captureSession)
                    .frame(height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(borderColor, lineWidth: 3)
                    )
                    .overlay {
                        if recording {
                            Text("\(secondsRemaining)")
                                .font(.system(size: 72, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                        }
                    }
                    .padding(.horizontal)
            }

            // Status labels
            if (phase == .rightArm || phase == .leftArm) && !recording && poseService.isBodyDetected {
                Label("Body detected -- recording will start", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
            }

            if recording {
                Label("Recording -- just do your best", systemImage: "record.circle")
                    .foregroundStyle(.red)
                    .font(.headline)
            }

            if phase == .transition {
                Spacer()

                Image(systemName: "hand.point.right.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, value: phase)

                Spacer()

                Button {
                    beginPhase(.leftArm)
                } label: {
                    Text("Ready -- Check Left Arm")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            if phase == .done {
                Label("Arms check recorded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            Spacer()

            if phase == .done {
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
        .onAppear {
            poseService.startSession()
        }
        .onDisappear {
            poseService.stopSession()
            cancelTimer()
        }
        .onChange(of: poseService.isBodyDetected) { _, detected in
            guard (phase == .rightArm || phase == .leftArm),
                  !recording, detected else { return }
            startRecording()
        }
    }

    // MARK: - Phase management

    private func beginPhase(_ newPhase: ArmCheckPhase) {
        phase = newPhase
        if newPhase == .leftArm {
            poseService.startSession()
        }
    }

    // MARK: - Recording

    private func startRecording() {
        recording = true
        secondsRemaining = recordingDuration
        poseService.uncappedBuffer = true
        poseService.clearBuffer()

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if secondsRemaining <= 1 {
                finishRecording()
            } else {
                secondsRemaining -= 1
            }
        }
    }

    private func finishRecording() {
        cancelTimer()
        recording = false
        poseService.uncappedBuffer = false

        switch phase {
        case .rightArm:
            rightArmResult = poseService.captureSnapshotForArm(.right) ?? (0, 0)
            poseService.stopSession()
            phase = .transition

        case .leftArm:
            leftArmResult = poseService.captureSnapshotForArm(.left) ?? (0, 0)
            poseService.stopSession()

            let right = rightArmResult ?? (0, 0)
            let left = leftArmResult ?? (0, 0)
            baselineManager.stagedArmMetrics = ArmMetrics(
                leftArmRaiseAngle: left.angle,
                rightArmRaiseAngle: right.angle,
                steadinessScore: (left.steadiness + right.steadiness) / 2.0
            )
            phase = .done

        default:
            break
        }
    }

    private func cancelTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}

#Preview {
    NavigationStack {
        CheckArmsView()
            .environment(BaselineManager())
    }
}
