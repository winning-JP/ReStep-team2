import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject private var session: AuthSession
    @AppStorage("restep.onboarding.completed") private var didCompleteOnboarding: Bool = false
    @AppStorage("restep.onboarding.userId") private var onboardedUserId: String = ""

    private var needsOnboarding: Bool {
        guard let loginId = session.user?.loginId, loginId.isEmpty == false else { return false }
        if didCompleteOnboarding == false { return true }
        return onboardedUserId != loginId
    }

    var body: some View {
        Group {
            if session.didRestore == false {
                Color.clear
            } else if session.isLoggedIn {
                if needsOnboarding {
                    OnboardingFlowView()
                        .environmentObject(session)
                } else {
                    ContentView()
                        .environmentObject(session)
                }
            } else {
                switch session.route {
                case .login:
                    LoginView()
                        .environmentObject(session)

                case .register:
                    RegisterView()
                        .environmentObject(session)
                }
            }
        }
        .onChange(of: session.user?.loginId) { _, newId in
            guard let loginId = newId, loginId.isEmpty == false else { return }
            if onboardedUserId != loginId {
                didCompleteOnboarding = false
            }
        }
    }
}
