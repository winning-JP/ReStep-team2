import SwiftUI

struct TermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("利用規約")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)

                TermsSection(title: "第1条（適用）", content: """
本規約は、ReStep（以下「本サービス」）の利用条件を定めるものです。利用者は本規約に同意のうえ、本サービスを利用するものとします。
""")

                TermsSection(title: "第2条（定義）", content: """
本規約において「利用者」とは、本サービスを閲覧・操作するすべての方をいいます。「当社」とは、本サービスを提供する運営者をいいます。
""")

                TermsSection(title: "第3条（利用登録）", content: """
本サービスの利用にあたり、当社が指定する方法で利用登録を行う場合があります。登録情報に虚偽があった場合、当社は利用停止等の措置を行うことがあります。
""")

                TermsSection(title: "第4条（アカウント管理）", content: """
利用者は自己の責任においてアカウント情報を管理するものとします。第三者による不正利用が発生した場合でも、当社は一切の責任を負いません。
""")

                TermsSection(title: "第5条（禁止事項）", content: """
利用者は以下の行為をしてはなりません。
・法令または公序良俗に反する行為
・他者の権利を侵害する行為
・不正アクセス、システムへの過度な負荷を与える行為
・本サービスの運営を妨げる行為
""")

                TermsSection(title: "第6条（健康データの取扱い）", content: """
本サービスはヘルスケア（歩数等）のデータを参照します。利用者は端末の設定からアクセス許可を管理できます。取得したデータは、サービス提供のためにのみ使用されます。
""")

                TermsSection(title: "第7条（利用料金）", content: """
本サービスは日本国内向けに無料で提供されます。将来的に有料機能を追加する場合、事前に通知します。
""")

                TermsSection(title: "第8条（知的財産権）", content: """
本サービスに関する著作権、商標権その他の知的財産権は当社または正当な権利者に帰属します。利用者は当社の許可なく複製・改変・転載等を行ってはなりません。
""")

                TermsSection(title: "第9条（投稿内容・入力情報）", content: """
利用者が本サービスに入力した情報の権利は利用者に帰属します。当社はサービス提供・改善のために必要な範囲で当該情報を利用できるものとします。
""")

                TermsSection(title: "第10条（免責事項）", content: """
本サービスの内容は利用者の健康状態を保証するものではありません。データの正確性・完全性について当社は保証しません。利用者は自己の判断と責任において本サービスを利用するものとします。
""")

                TermsSection(title: "第11条（サービスの変更・停止）", content: """
当社は、利用者への事前通知なく、本サービスの内容の変更または提供の停止を行うことがあります。
""")

                TermsSection(title: "第12条（メンテナンス・障害）", content: """
当社は本サービスの保守点検、システム障害、天災その他やむを得ない事情により、事前通知なくサービス提供を一時中断することがあります。
""")

                TermsSection(title: "第13条（通知・連絡方法）", content: """
当社から利用者への通知は、本サービス内の表示または当社が適当と判断する方法で行います。利用者から当社への連絡は、当社が指定する方法によって行うものとします。
""")

                TermsSection(title: "第14条（広告・プロモーション）", content: """
当社は本サービス内に広告またはプロモーション情報を表示する場合があります。
""")

                TermsSection(title: "第15条（外部サービス連携）", content: """
本サービスは外部サービス（例：Apple Health）と連携する場合があります。連携により取得される情報は、外部サービスの利用規約・プライバシーポリシーにも従うものとします。
""")

                TermsSection(title: "第16条（位置情報の取扱い）", content: """
本サービスが位置情報を利用する場合、利用者は端末の設定で許可を管理できます。位置情報はサービス提供に必要な範囲でのみ利用されます。
""")

                TermsSection(title: "第17条（データの保管・削除）", content: """
当社はサービス提供に必要な範囲で利用者情報を保管します。保管期間や削除方法は当社の定める方法に従います。利用者はアカウント削除によりデータ削除を申請できます。
""")

                TermsSection(title: "第18条（規約の変更）", content: """
当社は必要に応じて本規約を変更することができます。変更後の規約は本サービス内への掲示その他当社が適当と判断する方法により告知します。
""")

                TermsSection(title: "第19条（未成年者の利用）", content: """
未成年者が利用する場合、保護者等の同意を得たうえで本サービスを利用するものとします。
""")

                TermsSection(title: "第20条（利用停止・登録抹消）", content: """
当社は、利用者が本規約に違反した場合、事前の通知なく利用停止または登録抹消を行うことがあります。
""")

                TermsSection(title: "第21条（アカウント削除）", content: """
利用者は当社の定める方法によりアカウント削除を申請できます。削除後はデータの復元ができない場合があります。
""")

                TermsSection(title: "第22条（推奨環境）", content: """
本サービスは最新のiOSに近いバージョンでの利用を推奨します。対応外の環境では正常に動作しない場合があります。
""")

                TermsSection(title: "第23条（反社会的勢力の排除）", content: """
利用者は反社会的勢力に該当しないことを表明し、将来にわたって該当しないことを保証するものとします。
""")

                TermsSection(title: "第24条（準拠法・裁判管轄）", content: """
本規約は日本法に準拠し、紛争が生じた場合は日本の裁判所を第一審の専属的合意管轄とします。
""")

                TermsSection(title: "事業者情報", content: """
事業者名：（ここに運営者名を記載してください）
所在地：（必要に応じて記載）
お問い合わせ：アプリ内「よくある質問・お問い合わせ」よりご連絡ください。
""")
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TermsSection: View {
    let title: String
    let content: String

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
struct TermsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TermsView()
        }
    }
}
#endif
