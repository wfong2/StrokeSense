import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("StrokeSense")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            Button {
                // TODO: Navigate to stroke check flow
            } label: {
                Text("I don't feel right\nCheck Me")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    HomeView()
}
