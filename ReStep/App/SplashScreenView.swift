import SwiftUI

struct SplashScreenView: View {
    let logoImageName: String
    let displayDuration: TimeInterval
    let onFinish: () -> Void

    @State private var hasScheduledTransition = false
    @State private var animateLogo = false

    init(
        logoImageName: String = "SplashLogo",
        displayDuration: TimeInterval = 1.4,
        onFinish: @escaping () -> Void
    ) {
        self.logoImageName = logoImageName
        self.displayDuration = displayDuration
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color("AccentColor"), Color("AccentColor").opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Image(logoImageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220)
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
                .scaleEffect(animateLogo ? 1 : 0.85)
                .opacity(animateLogo ? 1 : 0)
                .padding()
                .accessibilityHidden(true)
        }
        .onAppear {
            guard !hasScheduledTransition else { return }
            hasScheduledTransition = true

            withAnimation(.interpolatingSpring(stiffness: 65, damping: 10)) {
                animateLogo = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) {
                onFinish()
            }
        }
    }
}

struct SplashScreenView_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreenView(onFinish: {})
            .previewDisplayName("Splash")
    }
}
