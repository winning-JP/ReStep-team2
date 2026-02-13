import SwiftUI

struct PartyBuilderView: View {
    @StateObject private var viewModel = PartyViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("最大4人まで編成できます")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)

                    partyRow

                    VStack(spacing: 10) {
                        ForEach(viewModel.travelers) { traveler in
                            Button {
                                viewModel.toggleMember(traveler)
                            } label: {
                                PartyTravelerRow(traveler: traveler, isSelected: viewModel.isSelected(traveler))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("パーティ編成")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var partyRow: some View {
        let members = viewModel.travelers.filter { viewModel.party.memberIds.contains($0.id) }
        return HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                if index < members.count {
                    PartySlotView(name: members[index].name)
                } else {
                    PartySlotView(name: "空き")
                }
            }
        }
    }
}

private struct PartySlotView: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
    }
}

private struct PartyTravelerRow: View {
    let traveler: Traveler
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(traveler.name)
                    .font(.headline)
                Text(traveler.job)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(traveler.rarity.label)
                .font(.caption.weight(.semibold))
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.cyan)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#if DEBUG
@available(iOS 17, *)
struct PartyBuilderView_Previews: PreviewProvider {
    static var previews: some View {
        PartyBuilderView()
    }
}
#endif
