import SwiftUI

struct TravelerListView: View {
    @StateObject private var viewModel = TravelerListViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("旅人が集まり、迷宮が動き出します")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Button {
                            viewModel.addRandomTraveler()
                        } label: {
                            Text("旅人を迎える（デモ）")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.cyan)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 12)

                    ForEach(viewModel.travelers) { traveler in
                        NavigationLink {
                            TravelerDetailView(traveler: traveler)
                        } label: {
                            TravelerCard(traveler: traveler)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("旅人")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct TravelerCard: View {
    let traveler: Traveler

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(traveler.name)
                    .font(.title3.bold())
                Spacer()
                Text(traveler.rarity.label)
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }

            Text(traveler.job)
                .font(.body.weight(.semibold))
                .foregroundColor(.primary)

            Text("固有スキル：\(traveler.skill)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#if DEBUG
@available(iOS 17, *)
struct TravelerListView_Previews: PreviewProvider {
    static var previews: some View {
        TravelerListView()
    }
}
#endif
