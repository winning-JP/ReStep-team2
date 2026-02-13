import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("プライバシーポリシー")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)

                PolicySection(title: "1. 取得する情報") {
                    """
当社は、本サービスの提供にあたり、以下の情報を取得する場合があります。
・アカウント情報（ユーザーID、メールアドレス等）
・ヘルスケアデータ（歩数等）
・端末情報（OSバージョン等）
・利用状況に関する情報（アプリ内の操作履歴等）
"""
                }

                PolicySection(title: "2. 利用目的") {
                    """
取得した情報は、以下の目的で利用します。
・本サービスの提供、運営、改善
・不具合の調査、品質向上
・お問い合わせ対応
・重要なお知らせの通知
"""
                }

                PolicySection(title: "3. ヘルスケアデータの取扱い") {
                    """
ヘルスケア（歩数等）のデータは、利用者の同意と端末設定の許可に基づいて取得します。利用者は端末の設定でいつでもアクセス許可を変更できます。
"""
                }

                PolicySection(title: "4. 第三者提供") {
                    """
当社は、法令に基づく場合を除き、利用者の同意なく個人情報を第三者に提供しません。
"""
                }

                PolicySection(title: "5. 外部サービス連携") {
                    """
本サービスは外部サービス（例：Apple Health）と連携する場合があります。外部サービスのプライバシーポリシーも併せてご確認ください。
"""
                }

                PolicySection(title: "6. 広告・アクセス解析") {
                    """
当社は、サービス向上のために匿名の利用状況データを集計する場合があります。広告表示を行う場合は、本ポリシーに明記のうえ周知します。
"""
                }

                PolicySection(title: "7. 安全管理") {
                    """
当社は、取得した情報の漏えい・滅失・毀損の防止のため、適切な安全管理措置を講じます。
"""
                }

                PolicySection(title: "8. 保管期間・削除") {
                    """
当社は、利用目的に必要な期間に限り情報を保管します。アカウント削除の申請があった場合、合理的な範囲で削除します。
"""
                }

                PolicySection(title: "9. 未成年者の利用") {
                    """
未成年者が本サービスを利用する場合、保護者等の同意を得た上で利用するものとします。
"""
                }

                PolicySection(title: "10. お問い合わせ") {
                    """
個人情報の取扱いに関するお問い合わせは、アプリ内「よくある質問・お問い合わせ」よりご連絡ください。
"""
                }

                PolicySection(title: "11. 改定") {
                    """
当社は本ポリシーを必要に応じて変更することがあります。変更後の内容は本サービス内に掲示します。
"""
                }

                PolicySection(title: "事業者情報") {
                    """
事業者名：（ここに運営者名を記載してください）
所在地：（必要に応じて記載）
"""
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PolicySection: View {
    let title: String
    let content: String

    init(title: String, content: @escaping () -> String) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.body)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
@available(iOS 17, *)
struct PrivacyPolicyView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PrivacyPolicyView()
        }
    }
}
#endif
