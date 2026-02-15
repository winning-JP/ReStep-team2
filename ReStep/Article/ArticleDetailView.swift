import SwiftUI

struct ArticleDetailView: View {
    let articleId: Int

    @State private var article: ArticleDetailResponse?
    @State private var isLoading = true
    @State private var isReacting = false
    @State private var errorMessage: String?

    private let api = ArticleAPIClient.shared

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if let article {
                VStack(alignment: .leading, spacing: 16) {
                    // ヘッダー
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(article.nickname)
                                .font(.subheadline.bold())
                            Text(formatDate(article.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    // タイトル
                    Text(article.title)
                        .font(.title2.bold())

                    Divider()

                    // 本文
                    Text(article.body)
                        .font(.body)

                    Divider()

                    // 統計＆リアクション
                    HStack(spacing: 24) {
                        Label("\(article.viewCount)", systemImage: "eye")
                            .foregroundStyle(.secondary)

                        Button {
                            Task { await toggleReaction() }
                        } label: {
                            Label(
                                "\(article.reactionCount)",
                                systemImage: article.userReactions.contains("like") ? "heart.fill" : "heart"
                            )
                            .foregroundStyle(article.userReactions.contains("like") ? .red : .secondary)
                        }
                        .disabled(isReacting)

                        Spacer()
                    }
                    .font(.subheadline)
                }
                .padding()
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle("記事詳細")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await loadDetail() } }
    }

    private func loadDetail() async {
        isLoading = true
        do {
            article = try await api.fetchArticleDetail(articleId: articleId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleReaction() async {
        isReacting = true
        do {
            let response = try await api.react(articleId: articleId, type: "like")
            if var a = article {
                a = ArticleDetailResponse(
                    id: a.id,
                    userId: a.userId,
                    nickname: a.nickname,
                    title: a.title,
                    body: a.body,
                    imageUrl: a.imageUrl,
                    viewCount: a.viewCount,
                    reactionCount: response.reactionCount,
                    createdAt: a.createdAt,
                    userReactions: response.added
                        ? (a.userReactions + ["like"])
                        : a.userReactions.filter { $0 != "like" }
                )
                article = a
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isReacting = false
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.locale = Locale(identifier: "ja_JP")
        display.dateFormat = "yyyy年M月d日 HH:mm"
        return display.string(from: date)
    }
}
