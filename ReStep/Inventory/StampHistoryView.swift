import SwiftUI

struct StampHistoryView: View {
    @State private var items: [StampHistoryItem] = []
    @State private var nextBeforeId: Int?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    private let wallet = WalletAPIClient.shared

    var body: some View {
        List {
            if items.isEmpty && isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if items.isEmpty {
                Text("履歴がありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.reason ?? item.type)
                                .font(.subheadline.weight(.semibold))
                            Text(formattedDate(item.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(deltaText(item.delta))
                                .font(.headline.weight(.bold))
                                .foregroundColor(item.delta >= 0 ? .green : .red)
                            Text("残り \(item.balanceAfter)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if nextBeforeId != nil {
                    HStack {
                        Spacer()
                        Button {
                            Task { await loadMore() }
                        } label: {
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Text("もっと見る")
                            }
                        }
                        .disabled(isLoadingMore)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("スタンプ履歴")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInitial()
        }
        .alert("エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await wallet.fetchStampHistory(limit: 50, beforeId: nil)
            items = response.items
            nextBeforeId = response.nextBeforeId
        } catch let apiErr as APIError {
            errorMessage = apiErr.userMessage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, let before = nextBeforeId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response = try await wallet.fetchStampHistory(limit: 50, beforeId: before)
            items.append(contentsOf: response.items)
            nextBeforeId = response.nextBeforeId
        } catch let apiErr as APIError {
            errorMessage = apiErr.userMessage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedDate(_ db: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: db) {
            let out = DateFormatter()
            out.locale = Locale(identifier: "ja_JP")
            out.dateStyle = .medium
            out.timeStyle = .short
            return out.string(from: date)
        }
        return db
    }

    private func deltaText(_ delta: Int) -> String {
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(delta)"
    }
}

#if DEBUG
struct StampHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            StampHistoryView()
        }
    }
}
#endif

