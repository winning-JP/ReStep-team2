import SwiftUI

struct ArticleComposeView: View {
    let onPosted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var isPosting = false
    @State private var showConfirm = false
    @State private var coinBalance: Int?
    @State private var errorMessage: String?

    private let api = ArticleAPIClient.shared
    private let wallet = WalletAPIClient.shared
    private let postCost = 50

    var canPost: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !bodyText.trimmingCharacters(in: .whitespaces).isEmpty &&
        (coinBalance ?? 0) >= postCost
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("タイトル", text: $title)
                    TextField("本文", text: $bodyText, axis: .vertical)
                        .lineLimit(5...20)
                }

                Section {
                    HStack {
                        Text("投稿コスト")
                        Spacer()
                        Text("\(postCost)コイン")
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        Text("所持コイン")
                        Spacer()
                        if let balance = coinBalance {
                            Text("\(balance)")
                                .foregroundColor(balance >= postCost ? .primary : .red)
                        } else {
                            ProgressView()
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("記事を投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("投稿") { showConfirm = true }
                        .disabled(!canPost || isPosting)
                }
            }
            .onAppear { Task { await loadBalance() } }
            .alert("記事を投稿", isPresented: $showConfirm) {
                Button("投稿する (\(postCost)コイン)") { Task { await postArticle() } }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("\(postCost)コインを消費して記事を投稿しますか？")
            }
        }
    }

    private func loadBalance() async {
        do {
            let response = try await wallet.fetchBalance()
            coinBalance = response.balance
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func postArticle() async {
        isPosting = true
        errorMessage = nil
        do {
            _ = try await api.postArticle(
                title: title.trimmingCharacters(in: .whitespaces),
                body: bodyText.trimmingCharacters(in: .whitespaces),
                imageUrl: nil
            )
            onPosted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isPosting = false
    }
}
