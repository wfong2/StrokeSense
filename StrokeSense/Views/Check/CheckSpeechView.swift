import SwiftUI

struct CheckSpeechView: View {
    @Environment(BaselineManager.self) private var baselineManager

    var body: some View {
        SpeechTestView(context: .check, tint: .red) { metrics in
            baselineManager.stagedSpeechMetrics = metrics
        } next: {
            CheckResultsView()
        }
        .navigationTitle("Step 3 of 3")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CheckSpeechView()
            .environment(BaselineManager())
    }
}
