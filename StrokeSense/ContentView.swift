import SwiftUI

struct ContentView: View {
    @State private var baselineManager = BaselineManager()

    var body: some View {
        if baselineManager.hasBaseline {
            HomeView()
                .environment(baselineManager)
        } else {
            NavigationStack {
                BaselineWelcomeView()
            }
            .environment(baselineManager)
        }
    }
}

#Preview {
    ContentView()
}
