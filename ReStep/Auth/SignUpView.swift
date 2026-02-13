import SwiftUI

struct SignUpView: View {
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false

    @State private var userId: String = ""
    @State private var email: String = ""
    @State private var password: String = ""

    var body: some View {
        ZStack {
            Color(.systemGray5).ignoresSafeArea()

            VStack {
                Spacer()

                VStack(spacing: 18) {
                    Text("新規登録")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top, 6)

                    VStack(spacing: 12) {
                        IconTextField(
                            systemImage: "person",
                            placeholder: "ユーザーID",
                            text: $userId
                        )

                        IconTextField(
                            systemImage: "envelope",
                            placeholder: "メールアドレス",
                            text: $email,
                            keyboard: .emailAddress
                        )

                        IconSecureField(
                            systemImage: "lock",
                            placeholder: "パスワード",
                            text: $password
                        )
                    }

                    Button {
                        guard !userId.isEmpty, !email.isEmpty, !password.isEmpty else { return }
                        isLoggedIn = true
                    } label: {
                        Text("登録")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 0.45, green: 0.80, blue: 0.92))
                            .clipShape(Capsule())
                            .shadow(radius: 2, y: 2)
                    }
                    .padding(.top, 4)
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(Color(red: 0.55, green: 0.90, blue: 0.95), lineWidth: 3)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
                )
                .padding(.horizontal, 26)

                Spacer()
            }
        }
    }
}


private struct IconTextField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(.gray)
                .frame(width: 22)

            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        )
    }
}

private struct IconSecureField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(.gray)
                .frame(width: 22)

            SecureField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        )
    }
}
