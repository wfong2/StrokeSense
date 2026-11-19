import SwiftUI

struct BaselineSpeechView: View {
    @Environment(BaselineManager.self) private var baselineManager

    var body: some View {
        SpeechTestView(context: .baseline, tint: .accentColor) { metrics in
            baselineManager.stagedSpeechMetrics = metrics
        } next: {
            BaselineCompleteView()
        }
        .navigationTitle("Step 3 of 3")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BaselineSpeechView()
            .environment(BaselineManager())
    }
}
