import SwiftUI

struct FaqContactView: View {
    @State private var subject: String = ""
    @State private var message: String = ""
    @State private var expandedFAQIDs: Set<String> = []

    private let faqs: [FaqItem] = [
        FaqItem(
            question: "歩数が反映されません",
            answer: "ヘルスケアのアクセス許可がオフになっている可能性があります。iPhoneの「設定」→「プライバシーとセキュリティ」→「ヘルスケア」で本アプリを許可し、アプリを再起動してください。"
        ),
        FaqItem(
            question: "ログインできません",
            answer: "ユーザーID/メールアドレスとパスワードを再確認してください。パスワードの前後にスペースが入っていないかも確認してください。解決しない場合は「お問い合わせ」からご連絡ください。"
        ),
        FaqItem(
            question: "通知が届きません",
            answer: "アプリ内の通知設定と、iPhoneの「設定」→「通知」→本アプリの許可をご確認ください。省電力モード中は通知が遅れる場合があります。"
        ),
        FaqItem(
            question: "アバターが表示されません",
            answer: "通信状況が不安定な場合に読み込みが失敗することがあります。Wi‑Fi環境で再度お試しください。改善しない場合はアプリの再起動をお試しください。"
        ),
        FaqItem(
            question: "目標設定の変更が保存されません",
            answer: "入力後に「変更を保存」をタップしたかをご確認ください。アプリを終了すると未保存の変更は反映されません。"
        ),
        FaqItem(
            question: "ログアウトするとデータは消えますか？",
            answer: "ログアウトではデータは削除されません。端末を変更した場合は、同じユーザーID/メールアドレスでログインすると復元できます。"
        )
    ]

    private var cardBackground: Color { Color(.secondarySystemBackground) }
    private var fieldBackground: Color { Color(.tertiarySystemBackground) }
    private var pageBackground: Color { Color(.systemGroupedBackground) }
    private var cardStroke: Color { Color.cyan.opacity(0.45) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    Text("お問い合わせ")
                        .font(.title2.bold())
                    VStack(spacing: 12) {
                        TextField(
                            "",
                            text: $subject,
                            prompt: Text("件名")
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.primary)
                        .padding()
                        .background(fieldBackground)
                        .cornerRadius(12)

                        TextField(
                            "",
                            text: $message,
                            prompt: Text("お問い合わせ内容")
                        , axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.primary)
                        .padding()
                        .frame(minHeight: 120, alignment: .topLeading)
                        .background(fieldBackground)
                        .cornerRadius(12)

                        Button {
                            // TODO: send
                            print("送信 tapped")
                        } label: {
                            Text("送信")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.cyan)
                                .cornerRadius(18)
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .cornerRadius(28)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(cardStroke, lineWidth: 1.5)
                )
                .shadow(radius: 10)

                VStack(spacing: 12) {
                    Text("よくある質問")
                        .font(.title2.bold())
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(faqs) { item in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedFAQIDs.contains(item.id) },
                                    set: { isOpen in
                                        if isOpen {
                                            expandedFAQIDs.insert(item.id)
                                        } else {
                                            expandedFAQIDs.remove(item.id)
                                        }
                                    }
                                )
                            ) {
                                Text(item.answer)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .padding(.top, 4)
                            } label: {
                                Text(item.question)
                                    .font(.body.weight(.semibold))
                                    .underline()
                                    .foregroundColor(.primary)
                            }

                            Divider()
                                .background(Color.secondary.opacity(0.5))
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1.5)
                )
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .background(pageBackground)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FaqItem: Identifiable {
    let question: String
    let answer: String
    var id: String { question }
}

#if DEBUG
@available(iOS 17, *)
struct FaqContactView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FaqContactView()
        }
    }
}
#endif
