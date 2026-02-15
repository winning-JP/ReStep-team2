import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRChallengeView: View {
    @State private var userId: Int?
    @State private var qrImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ヘッダー
                VStack(spacing: 8) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)

                    Text("RIZAP / chocoZAP 体験")
                        .font(.title2.bold())

                    Text("このQRコードを店舗で提示してください")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // QRコード表示
                if let qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.1), radius: 8)
                } else {
                    ProgressView()
                        .frame(width: 220, height: 220)
                }

                // 説明
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(icon: "1.circle.fill", text: "QRコードを店舗スタッフに見せる")
                    InfoRow(icon: "2.circle.fill", text: "体験プランの説明を受ける")
                    InfoRow(icon: "3.circle.fill", text: "体験を楽しむ")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 4)
                )

                Text("※ このQRコードは体験参加の受付用です")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("体験QRコード")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { generateQR() }
    }

    private func generateQR() {
        // ユーザーIDを取得してQRコード生成
        Task {
            do {
                let status = try await UserAPIClient.shared.status()
                let loginId = status.user?.loginId ?? "unknown"
                let data = "restep://chocozap-trial?user=\(loginId)&t=\(Int(Date().timeIntervalSince1970))"
                qrImage = generateQRCodeImage(from: data)
            } catch {
                let fallback = "restep://chocozap-trial?t=\(Int(Date().timeIntervalSince1970))"
                qrImage = generateQRCodeImage(from: fallback)
            }
        }
    }

    private func generateQRCodeImage(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scale = 10.0
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.title3)
            Text(text)
                .font(.subheadline)
        }
    }
}
