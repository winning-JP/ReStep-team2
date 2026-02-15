import SwiftUI

struct ArticleListView: View {
    @State private var articles: [ArticleItem] = []
    @State private var sortMode = "new"
    @State private var isLoading = false
    @State private var showCompose = false
    @State private var total = 0
    @State private var errorMessage: String?

    private let api = ArticleAPIClient.shared

    var body: some View {
        VStack(spacing: 0) {
            // ソートタブ
            Picker("ソート", selection: $sortMode) {
                Text("新着").tag("new")
                Text("人気").tag("popular")
                Text("閲覧数").tag("views")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onChange(of: sortMode) {
                Task { await loadArticles() }
            }

            if isLoading && articles.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if articles.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("記事がありません")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(articles) { article in
                            NavigationLink {
                                ArticleDetailView(articleId: article.id)
                            } label: {
                                ArticleCardView(article: article)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("記事")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCompose = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .onAppear { Task { await loadArticles() } }
        .sheet(isPresented: $showCompose) {
            ArticleComposeView {
                Task { await loadArticles() }
            }
        }
    }

    private func loadArticles() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await api.fetchArticles(sort: sortMode, limit: 50, offset: 0)
            articles = response.items
            total = response.total
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct ArticleCardView: View {
    let article: ArticleItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.secondary)
                Text(article.nickname)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatDate(article.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(article.title)
                .font(.headline)
                .lineLimit(2)

            Text(article.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 16) {
                Label("\(article.viewCount)", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(article.reactionCount)", systemImage: "heart")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "ja_JP")
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
