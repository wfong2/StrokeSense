import SwiftUI

struct ContentView: View {
    @State private var baselineManager = BaselineManager()

    // Always start with onboarding for dev/testing
    // TODO: Restore baseline check once mature
    // if baselineManager.hasBaseline { HomeView() } else { onboarding }
    var body: some View {
        NavigationStack {
            BaselineWelcomeView()
        }
        .environment(baselineManager)
    }
}

#Preview {
    ContentView()
}
