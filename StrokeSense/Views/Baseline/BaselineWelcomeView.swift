import SwiftUI

struct BaselineWelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.stand")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Set Your Baseline")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("StrokeSense needs to learn what's normal for you. We'll capture a quick baseline of your face, arms, and speech so we can detect changes later.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()

            NavigationLink {
                BaselineFaceView()
            } label: {
                Text("Get Started")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Welcome")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BaselineWelcomeView()
    }
}
