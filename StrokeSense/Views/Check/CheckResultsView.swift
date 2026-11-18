import SwiftUI
import MapKit

private struct DismissCheckFlowKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var dismissCheckFlow: @Sendable () -> Void {
        get { self[DismissCheckFlowKey.self] }
        set { self[DismissCheckFlowKey.self] = newValue }
    }
}

struct CheckResultsView: View {
    @Environment(BaselineManager.self) private var baselineManager
    @Environment(\.dismissCheckFlow) private var dismissCheckFlow

    @State private var callCountdown: Int?
    @State private var countdownTimer: Timer?
    @State private var timerCancelled = false
    @State private var llmSummary: String?
    @State private var urgentCareResults: [MKMapItem] = []

    private var baseline: BaselineData? {
        baselineManager.load()
    }

    private var currentFace: FaceMetrics {
        baselineManager.stagedFaceMetrics ?? FaceMetrics(
            leftEyeOpenProbability: 0.93,
            rightEyeOpenProbability: 0.94,
            mouthSmileLeft: 0.78,
            mouthSmileRight: 0.79,
            mouthCornerTilt: 0.02
        )
    }

    /// Nil when the arm step was skipped. No placeholder values: a missing
    /// measurement must show as incomplete, never as a real score.
    private var currentArms: ArmMetrics? {
        baselineManager.stagedArmMetrics
    }

    /// Arm check ran but didn't get enough good frames for one or both arms.
    private var armsIncomplete: Bool {
        !DevFlags.skipArms && currentArms?.holdScore == nil
    }

    private var currentSpeech: SpeechMetrics {
        baselineManager.stagedSpeechMetrics ?? SpeechMetrics(
            clarity: 0.90,
            wordsPerMinute: 125.0,
            samplePhrase: "The quick brown fox jumps over the lazy dog."
        )
    }

    // MARK: - Drop from baseline & severity

    /// All scores are 0–1 with higher = better. A drop is measured in points
    /// (0–100 scale) so a low baseline can't inflate it, and only a decline
    /// counts — scoring better than baseline is never a warning sign.
    private static let minorDropPoints = 10.0
    private static let significantDropPoints = 25.0

    private func dropPoints(baseline: Double?, current: Double?) -> Double? {
        guard let baselineVal = baseline, let current else { return nil }
        return (baselineVal - current) * 100.0
    }

    /// Face score: landmark geometry only; the AI model is info only (shown,
    /// not scored). On-device it swung 100% → 17% on a normal face, so even a
    /// 20% weight caused false alerts. Raise this below 1.0 only after a
    /// retrained model beats geometry on the same test set.
    private static let geometryWeight = 1.0

    private func faceScore(_ metrics: FaceMetrics) -> Double {
        let geometry = metrics.geometrySymmetry
        guard let mlProb = metrics.mlProbability else { return geometry }
        return Self.geometryWeight * geometry + (1.0 - Self.geometryWeight) * (1.0 - mlProb)
    }

    private var currentFaceScore: Double {
        faceScore(currentFace)
    }

    private var baselineFaceScore: Double? {
        baseline?.faceMetrics.map { faceScore($0) }
    }

    private var faceDrop: Double? {
        dropPoints(baseline: baselineFaceScore, current: currentFaceScore)
    }


    /// Arm Drift score per arm: 80% motion rules (drift, turn, shake) + 20% AI
    /// (1 − drift probability), same split the face used. The weaker arm decides.
    /// Without the model it's 100% rules. The AI is trained on synthetic holds
    /// so far; watch its line in the breakdown for swings on real recordings.
    private static let armRuleWeight = 0.8

    /// How much lower the arm is held than at baseline, in degrees, beyond which
    /// it starts to count. Steady checks varied up to ~7° from wrist angle alone.
    private static let sagAllowance = 8.0
    /// Sag beyond the allowance at which the sag score reaches 0.
    private static let sagRange = 20.0

    /// Degrees the arm is held lower than the same arm at baseline (+ = lower).
    private func sag(_ r: ArmRecording?, vs base: ArmRecording?) -> Double? {
        guard let now = r?.meanElevation, let then = base?.meanElevation,
              r?.isComplete == true, base?.isComplete == true else { return nil }
        return then - now
    }

    /// Rules score for one arm: the worse of "stayed put during the hold"
    /// (drift, turn, shake) and "held as high as at baseline". A patient whose
    /// arm is already sagging when the recording starts may hold steady at a
    /// low level, so drift alone would miss it.
    private func armRules(_ r: ArmRecording?, vs base: ArmRecording?) -> Double? {
        guard let hold = r?.holdScore else { return nil }
        guard let sag = sag(r, vs: base) else { return hold }
        let sagScore = 1.0 - min(max(sag - Self.sagAllowance, 0) / Self.sagRange, 1.0)
        return min(hold, sagScore)
    }

    /// Pass the baseline's arms as `comparedTo` when scoring a check; the
    /// baseline itself is scored on its own (no sag).
    private func armScore(_ metrics: ArmMetrics?, comparedTo base: ArmMetrics? = nil) -> Double? {
        func one(_ r: ArmRecording?, _ b: ArmRecording?) -> Double? {
            guard let r, let rules = armRules(r, vs: b) else { return nil }
            guard let p = ArmClassifierService.shared.driftProbability(r) else { return rules }
            return Self.armRuleWeight * rules + (1.0 - Self.armRuleWeight) * (1.0 - p)
        }
        guard let left = one(metrics?.left, base?.left), let right = one(metrics?.right, base?.right) else { return nil }
        return min(left, right)
    }

    private var currentArmScore: Double? {
        armScore(currentArms, comparedTo: baseline?.armMetrics)
    }

    private var armHoldDrop: Double? {
        dropPoints(baseline: armScore(baseline?.armMetrics), current: currentArmScore)
    }

    /// Per-arm raw measurements under the arm cards, for calibration.
    private var armBreakdownText: String {
        func deg(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))°" } ?? "–" }
        func arm(_ r: ArmRecording?) -> String {
            guard let r else { return "–" }
            let status = !r.isGripUsable ? ", phone on its side" : r.isComplete ? "" : ", incomplete"
            let grip = r.gripName.map { ", \($0) grip" } ?? ""
            let shake = r.shake.map { String(format: "%.1f°", $0) } ?? "–"
            return "elev \(deg(r.meanElevation)), drift \(deg(r.drift)), turn \(deg(r.pronation)), shake \(shake), \(r.samples.count) readings\(grip)\(status)"
        }
        func line(_ label: String, _ m: ArmMetrics?) -> String {
            "\(label) L: \(arm(m?.left))\n\(label) R: \(arm(m?.right))"
        }
        return "\(line("Baseline", baseline?.armMetrics))\n\(line("Now", currentArms))\n\(armAIText)"
    }

    /// Both parts of the Arm Drift card per arm, as "staying put" (higher = better),
    /// the same direction as the card.
    private var armAIText: String {
        func pct(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "–" }
        func ai(_ r: ArmRecording?) -> Double? {
            r.flatMap { ArmClassifierService.shared.driftProbability($0) }.map { 1.0 - $0 }
        }
        func deg(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))°" } ?? "–" }
        let base = baseline?.armMetrics
        let baseRules = "L \(pct(base?.left?.holdScore)) R \(pct(base?.right?.holdScore))"
        let nowRules = "L \(pct(armRules(currentArms?.left, vs: base?.left))) R \(pct(armRules(currentArms?.right, vs: base?.right)))"
        let sagLine = "L \(deg(sag(currentArms?.left, vs: base?.left))) R \(deg(sag(currentArms?.right, vs: base?.right)))"
        func aiPair(_ m: ArmMetrics?) -> String { "L \(pct(ai(m?.left))) R \(pct(ai(m?.right)))" }
        return "Sag vs baseline (\(Int(Self.sagAllowance))° allowed): \(sagLine)\n"
            + "Rules (80%): baseline \(baseRules) · now \(nowRules)\n"
            + "AI (20%): baseline \(aiPair(base)) · now \(aiPair(currentArms))"
    }

    /// Nil when speech was skipped, so placeholder values never count.
    private var speechDrop: Double? {
        guard !DevFlags.skipSpeech else { return nil }
        return dropPoints(
            baseline: baseline?.speechMetrics?.clarity,
            current: currentSpeech.clarity
        )
    }

    /// Breakdown of the Face card, same direction as the card (higher = more symmetric).
    private var faceBreakdownText: String {
        func pct(_ p: Double) -> String { "\(Int((p * 100).rounded()))%" }
        let baseFace = baseline?.faceMetrics
        let geometry = "Geometry (scored): baseline \(baseFace.map { pct($0.geometrySymmetry) } ?? "–") · now \(pct(currentFace.geometrySymmetry))"
        func raw(_ m: FaceMetrics?) -> String {
            guard let m else { return "–" }
            let tilt = m.mouthCornerTilt.map { "\(Int(($0 * 100).rounded()))%" } ?? "none"
            return "tilt \(tilt), eyes \(pct(m.leftEyeOpenProbability))/\(pct(m.rightEyeOpenProbability))"
        }
        let rawLine = "Raw: baseline \(raw(baseFace)) · now \(raw(currentFace))"
        let ai: String
        if let now = currentFace.mlProbability {
            ai = "AI (info only): baseline \(baseFace?.mlProbability.map { pct(1.0 - $0) } ?? "not recorded") · now \(pct(1.0 - now))"
        } else {
            ai = "AI did not run (geometry only)"
        }
        return "\(geometry)\n\(ai)\n\(rawLine)"
    }

    private var flaggedCount: Int {
        [faceDrop, armHoldDrop, speechDrop]
            .compactMap { $0 }
            .filter { $0 >= Self.significantDropPoints }
            .count
    }

    private var hasMinorDrop: Bool {
        [faceDrop, armHoldDrop, speechDrop]
            .compactMap { $0 }
            .contains { $0 >= Self.minorDropPoints }
    }

    /// Number of significant drops, but never "Looking Good" while any check
    /// shows a minor drop — a visible change shouldn't get a green shield.
    private var severityLevel: Int {
        max(flaggedCount, hasMinorDrop ? 1 : 0)
    }

    /// An incomplete check never gets "Looking Good": the app can't vouch for
    /// what it couldn't measure.
    private var severityIcon: String {
        switch severityLevel {
        case 0 where armsIncomplete: return "questionmark.circle.fill"
        case 0: return "checkmark.shield.fill"
        case 1: return "exclamationmark.triangle.fill"
        case 2: return "exclamationmark.octagon.fill"
        default: return "xmark.shield.fill"
        }
    }

    private var severityTitle: String {
        switch severityLevel {
        case 0 where armsIncomplete: return "Check Incomplete"
        case 0: return "Looking Good"
        case 1: return "Be Aware"
        case 2: return "Getting Serious"
        default: return "Seek Help Now"
        }
    }

    private var severityColor: Color {
        switch severityLevel {
        case 0 where armsIncomplete: return .orange
        case 0: return .green
        case 1: return .orange
        default: return .red
        }
    }

    private var severitySubtitle: String {
        switch severityLevel {
        case 0 where armsIncomplete: return "The arm check could not be completed. If you have sudden symptoms, call 911."
        case 0: return "Your results are within normal range compared to your baseline."
        case 1 where flaggedCount == 0: return "A small change from your baseline was detected. Re-check in a few minutes."
        case 1: return "One area shows a significant change from your baseline."
        case 2: return "Multiple areas show significant changes from your baseline."
        default: return "Several areas show significant changes. Consider seeking medical attention."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Dynamic severity header
                Image(systemName: severityIcon)
                    .font(.system(size: 64))
                    .foregroundStyle(severityColor)

                Text(severityTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // LLM summary card
                if let summary = llmSummary {
                    Text(summary)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                } else {
                    Text(severitySubtitle)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                // 911 countdown UI
                if let countdown = callCountdown, !timerCancelled {
                    VStack(spacing: 12) {
                        Text("\(countdown)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                            .contentTransition(.numericText())

                        Text("Calling 911 in \(countdown) seconds...")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Button {
                            cancelTimer()
                        } label: {
                            Text("Cancel")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .padding(.horizontal)
                    }
                    .padding()
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }

                // Nearby urgent care (when 1 area flagged)
                if flaggedCount == 1 && !urgentCareResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Nearby Urgent Care", systemImage: "cross.case.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        ForEach(Array(urgentCareResults.enumerated()), id: \.offset) { _, item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Urgent Care")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(formatAddress(item.placemark))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    item.openInMaps(launchOptions: [
                                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                                    ])
                                } label: {
                                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                            }
                            if item !== urgentCareResults.last {
                                Divider()
                            }
                        }

                        Button {
                            if let url = URL(string: "maps://?q=urgent+care+near+me") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Show All in Maps", systemImage: "map.fill")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                    .padding()
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }

                VStack(spacing: 16) {
                    resultCard(
                        title: "Face Symmetry",
                        icon: "face.smiling",
                        baselineValue: baselineFaceScore,
                        currentValue: currentFaceScore,
                        unit: "symmetry"
                    )

                    Label(
                        faceBreakdownText,
                        systemImage: "cpu"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // Arm Position isn't a card: the phone can't tell arm height
                    // from wrist angle. Elevation stays in the raw line below.
                    if !DevFlags.skipArms {
                        resultCard(
                            title: "Arm Drift",
                            icon: "arrow.down.right",
                            baselineValue: armScore(baseline?.armMetrics),
                            currentValue: currentArmScore,
                            unit: "hold"
                        )

                        Label(armBreakdownText, systemImage: "figure.stand")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !DevFlags.skipSpeech {
                        resultCard(
                            title: "Speech Clarity",
                            icon: "waveform",
                            baselineValue: baseline?.speechMetrics?.clarity,
                            currentValue: currentSpeech.clarity,
                            unit: "clarity"
                        )
                    }
                }
                .padding(.horizontal)

                Button {
                    cancelTimer()
                    baselineManager.clearStaged()
                    dismissCheckFlow()
                } label: {
                    Text(flaggedCount >= 2 && !timerCancelled ? "I'm OK — Dismiss" : "Done")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .padding(.vertical)
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .onAppear {
            if flaggedCount >= 2 {
                startCountdown()
            }
        }
        .task {
            await fetchLLMSummary()
        }
        .task {
            if flaggedCount == 1 {
                await searchNearbyUrgentCare()
            }
        }
        .onDisappear {
            cancelTimer()
        }
    }

    // MARK: - Timer

    private func startCountdown() {
        callCountdown = 10
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard let current = callCountdown, current > 1 else {
                cancelTimer()
                // TODO: Replace with tel://911 for production
                print("[DEV] 911 call would be placed now")
                return
            }
            callCountdown = current - 1
        }
    }

    private func cancelTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        if callCountdown != nil {
            timerCancelled = true
            callCountdown = nil
        }
    }

    // MARK: - Nearby Urgent Care

    private func searchNearbyUrgentCare() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "urgent care"
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            urgentCareResults = Array(response.mapItems.prefix(3))
        } catch {
            urgentCareResults = []
        }
    }

    private func formatAddress(_ placemark: MKPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }.joined(separator: " ")
        let parts = ([street, placemark.locality, placemark.administrativeArea] as [String?])
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Address unavailable" : parts.joined(separator: ", ")
    }

    // MARK: - LLM Summary

    private func fetchLLMSummary() async {
        let faceBaseline = baselineFaceScore
        let faceCurrent = currentFaceScore
        let speechBaseline = DevFlags.skipSpeech ? nil : baseline?.speechMetrics?.clarity
        let speechCurrent = currentSpeech.clarity

        let metrics = LLMService.CheckMetrics(
            severity: severityTitle,
            flaggedCount: flaggedCount,
            faceSymmetry: faceBaseline.map { b in
                LLMService.MetricPair(baseline: b, current: faceCurrent, dropPoints: faceDrop ?? 0)
            },
            armCheckIncomplete: armsIncomplete,
            armDrift: armPair(armScore(baseline?.armMetrics), currentArmScore, armHoldDrop),
            speechClarity: speechBaseline.map { b in
                LLMService.MetricPair(baseline: b, current: speechCurrent, dropPoints: speechDrop ?? 0)
            }
        )

        llmSummary = await LLMService.generateSummary(metrics: metrics)
    }

    private func armPair(_ baseline: Double?, _ current: Double?, _ drop: Double?) -> LLMService.MetricPair? {
        guard let baseline, let current else { return nil }
        return LLMService.MetricPair(baseline: baseline, current: current, dropPoints: drop ?? 0)
    }

    // MARK: - Result card

    private func resultCard(title: String, icon: String, baselineValue: Double?, currentValue: Double?, unit: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.red)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if currentValue == nil {
                    Label("Could not be completed", systemImage: "questionmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let baselineVal = baselineValue, let currentValue {
                    let drop = (baselineVal - currentValue) * 100.0

                    HStack(spacing: 4) {
                        Text("Baseline: \(Int(baselineVal * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Now: \(Int(currentValue * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        if drop >= Self.significantDropPoints {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text("Significant drop (\(String(format: "%.0f", drop)) pts)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if drop >= Self.minorDropPoints {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Minor drop (\(String(format: "%.0f", drop)) pts)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("Normal")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                } else {
                    Text("No baseline to compare")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        CheckResultsView()
            .environment(BaselineManager())
    }
}
