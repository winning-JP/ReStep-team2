import SwiftUI
import MessageUI

struct BluetoothDebugView: View {
    private struct MailDraft: Identifiable {
        let id = UUID()
        let body: String
    }

    @State private var logStore = BluetoothDebugLogStore.shared
    @State private var statusStore = BluetoothDebugStatusStore.shared
    @State private var mailDraft: MailDraft?
    @State private var showMailUnavailableAlert: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("状態")
                        .font(.subheadline.weight(.semibold))
                }
                statusRow("スキャン中", value: statusStore.isScanning ? "ON" : "OFF")
                statusRow("広告中", value: statusStore.isAdvertising ? "ON" : "OFF")
                statusRow("最後の検出", value: formatted(statusStore.lastDiscoveredAt))
                statusRow("最後のすれ違い", value: formatted(statusStore.lastEncounterAt))
                statusRow("最新受信ユーザーID", value: latestPayloadUserId())
            }
            .padding(8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button("ログを送信", action: sendLogsByMail)
                    .buttonStyle(.borderedProminent)
                Button("クリア", role: .destructive) {
                    logStore.clear()
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            if logStore.entries.isEmpty {
                Text("まだログがありません。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(logStore.entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(entry.message)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 6)
        .sheet(item: $mailDraft) { draft in
            MailComposerView(
                subject: "ReStep すれ違いデバッグログ",
                recipients: ["restep@winning.moe"],
                body: draft.body,
                onFinish: { mailDraft = nil }
            )
        }
        .alert("メール送信ができません", isPresented: $showMailUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("この端末にメールアカウントが設定されていません。")
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "なし" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private func latestPayloadUserId() -> String {
        guard let payload = logStore.payloads.first else { return "なし" }
        return payload.userId
    }

    private func sendLogsByMail() {
        if MFMailComposeViewController.canSendMail() {
            mailDraft = MailDraft(body: mailBody())
        } else {
            showMailUnavailableAlert = true
        }
    }

    private func mailBody() -> String {
        var lines: [String] = []
        lines.append("ReStep すれ違いデバッグログ")
        lines.append("送信日時: \(Date().formatted(date: .abbreviated, time: .standard))")
        lines.append("スキャン中: \(statusStore.isScanning ? "ON" : "OFF")")
        lines.append("広告中: \(statusStore.isAdvertising ? "ON" : "OFF")")
        lines.append("最後の検出: \(formatted(statusStore.lastDiscoveredAt))")
        lines.append("最後のすれ違い: \(formatted(statusStore.lastEncounterAt))")
        lines.append("")
        lines.append("ログ:")
        for entry in logStore.entries {
            let time = entry.date.formatted(date: .omitted, time: .standard)
            lines.append("\(time) \(entry.message)")
        }
        if !logStore.payloads.isEmpty {
            lines.append("")
            lines.append("受信ペイロード:")
            for payload in logStore.payloads {
                let time = payload.date.formatted(date: .omitted, time: .standard)
                lines.append("\(time) id=\(payload.userId) nickname=\(payload.nickname)")
                lines.append(payload.raw)
            }
        }
        return lines.joined(separator: "\n")
    }
}

#if DEBUG
@available(iOS 17, *)
struct BluetoothDebugView_Previews: PreviewProvider {
    static var previews: some View {
        BluetoothDebugView()
            .padding()
    }
}
#endif
