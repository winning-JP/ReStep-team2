import SwiftUI

struct EncounterLegendStartView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Image("legend_castle")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()

                NavigationLink {
                    PartyBuilderView()
                } label: {
                    Text("パーティ編集")
                        .font(.body.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                }

                NavigationLink {
                    DungeonView()
                } label: {
                    Text("ゲームスタート")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .clipShape(Capsule())
                }

                Button {
                    dismiss()
                } label: {
                    Text("戻る")
                        .font(.body.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.8))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }
}

#if DEBUG
@available(iOS 17, *)
struct EncounterLegendStartView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EncounterLegendStartView()
        }
    }
}
#endif
