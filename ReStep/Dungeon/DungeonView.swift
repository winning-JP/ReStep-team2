import SwiftUI
import UIKit

struct DungeonView: View {
    @StateObject private var viewModel = DungeonViewModel()
    private let retroFont = "CourierNewPS-BoldMT"
    @State private var showImpact = false
    @State private var impactNumber = "1"
    @State private var enemyHit = false
    @State private var playerHit = false
    @State private var screenShake = false
    @State private var enemyBob = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                retroBackground
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline.bold())
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }

                        Spacer()
                    }
                    .padding(.top, 6)

                    retroHeader

                    battleScene
                        .offset(x: screenShake ? -6 : 0)

                    if viewModel.isInBattle {
                        VStack(spacing: 8) {
                            HStack {
                                Text("行動：\(viewModel.currentAttackerName)")
                                    .font(.custom(retroFont, size: 12))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                Spacer()
                            }

                            HStack {
                                Text("残り攻撃回数 \(viewModel.remainingAttacks)")
                                    .font(.custom(retroFont, size: 12))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Button {
                                    viewModel.performAction(.attack)
                                } label: {
                                    Text("たたかう")
                                        .font(.custom(retroFont, size: 13))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(RetroButtonStyle(fill: Color(red: 0.95, green: 0.29, blue: 0.26)))

                                Button {
                                    viewModel.performAction(.skill)
                                } label: {
                                    Text("スキル")
                                        .font(.custom(retroFont, size: 13))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(RetroButtonStyle(fill: Color(red: 0.33, green: 0.62, blue: 0.95)))

                                Button {
                                    viewModel.performAction(.defend)
                                } label: {
                                    Text("ぼうぎょ")
                                        .font(.custom(retroFont, size: 13))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(RetroButtonStyle(fill: Color(red: 0.2, green: 0.8, blue: 0.7)))
                            }
                        }
                    } else {
                        Button {
                            viewModel.startRun()
                        } label: {
                            Text(viewModel.isRunning ? "探索中" : "迷宮へ行く")
                                .font(.custom(retroFont, size: 14))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(RetroButtonStyle(fill: Color(red: 1.0, green: 0.84, blue: 0.25)))
                        .disabled(viewModel.isRunning)
                    }

                    if !viewModel.resultText.isEmpty {
                        Text(viewModel.resultText)
                            .font(.custom(retroFont, size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    logCard
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .navigationBarHidden(true)
        }
        .onAppear { lockOrientation(.landscapeRight) }
        .onDisappear { lockOrientation(.portrait) }
        .onChange(of: viewModel.shouldExit) { _, newValue in
            if newValue {
                dismiss()
            }
        }
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BATTLE LOG")
                .font(.custom(retroFont, size: 12))
                .foregroundColor(.white)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.log.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color(red: 0.93, green: 0.83, blue: 0.2))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(viewModel.log[index])
                                .font(.custom(retroFont, size: 11))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var battleScene: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.23, blue: 0.48),
                            Color(red: 0.22, green: 0.58, blue: 0.74),
                            Color(red: 0.76, green: 0.86, blue: 0.44)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    ScanlineOverlay()
                        .opacity(0.18)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PLAYER")
                                .font(.custom(retroFont, size: 10))
                                .foregroundColor(.white)
                            HPBar(hp: viewModel.allyHp, maxHp: viewModel.allyMaxHp, isEnemy: false)
                                .frame(width: 110, height: 8)
                        }
                        AvatarThumbnailView(cameraDistanceMultiplier: 1.2)
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .offset(x: playerHit ? -8 : 0)
                    }

                    Spacer()

                    VStack(spacing: 6) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("ENEMY")
                                .font(.custom(retroFont, size: 10))
                                .foregroundColor(.white)
                            HPBar(hp: viewModel.enemyHp, maxHp: viewModel.enemyMaxHp, isEnemy: true)
                                .frame(width: 110, height: 8)
                        }
                        Image("enemy_slime")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 110)
                            .opacity(viewModel.enemyHp > 0 ? 1 : 0)
                            .scaleEffect(viewModel.enemyHp > 0 ? (enemyHit ? 0.9 : 1.0) : 0.7)
                            .offset(x: enemyHit ? 10 : 0, y: enemyBob ? -6 : 0)
                            .animation(.easeOut(duration: 0.35), value: viewModel.enemyHp)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }

            if showImpact {
                VStack(spacing: 4) {
                    Text(impactNumber)
                        .font(.custom(retroFont, size: 32))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    Image(systemName: "sparkle")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .transition(.scale.combined(with: .opacity))
            }

            if viewModel.isRunning {
                Text("TURN 1")
                    .font(.custom(retroFont, size: 14))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.5), lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) {
            HStack {
                Text(viewModel.lastActionText)
                    .font(.custom(retroFont, size: 11))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onChange(of: viewModel.log.count) { _, _ in
            triggerImpact()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                enemyBob = true
            }
        }
    }

    private func triggerImpact() {
        impactNumber = String(Int.random(in: 1...5))
        withAnimation(.easeOut(duration: 0.08)) {
            enemyHit = true
            playerHit = true
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            showImpact = true
        }
        withAnimation(.default) {
            screenShake = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.2)) {
                showImpact = false
            }
            withAnimation(.easeOut(duration: 0.12)) {
                enemyHit = false
                playerHit = false
                screenShake = false
            }
        }
    }
}

private func lockOrientation(_ orientation: UIInterfaceOrientation) {
    UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let rootViewController = scene.windows.first?.rootViewController {
        rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
	
private struct HPBar: View {
    let hp: Int
    let maxHp: Int
    let isEnemy: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.45))
                RoundedRectangle(cornerRadius: 2)
                    .fill(isEnemy ? Color(red: 0.98, green: 0.54, blue: 0.2) : Color(red: 0.2, green: 0.86, blue: 0.7))
                    .frame(width: geo.size.width * ratio)
            }
        }
    }

    private var ratio: CGFloat {
        guard maxHp > 0 else { return 0 }
        return CGFloat(max(0, hp)) / CGFloat(maxHp)
    }
}

private struct RetroButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.6), lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

private struct ScanlineOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let lineCount = Int(geo.size.height / 4)
            VStack(spacing: 0) {
                ForEach(0..<max(1, lineCount), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.12))
                        .frame(height: 1)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 3)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private extension DungeonView {
    var retroHeader: some View {
        HStack {
            Text("BATTLE")
                .font(.custom(retroFont, size: 16))
                .foregroundColor(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Text("STAGE 1")
                .font(.custom(retroFont, size: 12))
                .foregroundColor(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    var retroBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.1, blue: 0.18),
                Color(red: 0.12, green: 0.12, blue: 0.2),
                Color(red: 0.05, green: 0.06, blue: 0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            AngularGradient(
                colors: [
                    Color(red: 0.92, green: 0.7, blue: 0.2).opacity(0.08),
                    Color.clear,
                    Color(red: 0.2, green: 0.8, blue: 0.7).opacity(0.08),
                    Color.clear
                ],
                center: .topLeading
            )
        )
    }
}

#if DEBUG
@available(iOS 17, *)
struct DungeonView_Previews: PreviewProvider {
    static var previews: some View {
        DungeonView()
    }
}
#endif
