import SwiftUI

struct RegisterView: View {

    @EnvironmentObject private var session: AuthSession
    @Environment(\.colorScheme) private var colorScheme

    @State private var userId: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var showError = false
    @State private var errorMessage = "入力してください"

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 16) {
                Text("新規登録")
                    .font(.title2)
                    .fontWeight(.semibold)

                TextField(
                    "",
                    text: $userId,
                    prompt: Text("ユーザーID")
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                TextField(
                    "",
                    text: $email,
                    prompt: Text("メールアドレス")
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                SecureField(
                    "",
                    text: $password,
                    prompt: Text("パスワード")
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                )
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                SecureField(
                    "",
                    text: $confirmPassword,
                    prompt: Text("パスワード（再入力）")
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                )
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                Button {
                    guard !userId.isEmpty, !email.isEmpty, !password.isEmpty, !confirmPassword.isEmpty else {
                        errorMessage = "入力してください"
                        showError = true
                        return
                    }

                    guard password == confirmPassword else {
                        errorMessage = "パスワードが一致しません"
                        showError = true
                        return
                    }

                    Task {
                        let ok = await session.register(userId: userId, email: email, password: password)
                        if !ok {
                            errorMessage = session.lastErrorMessage ?? "登録に失敗しました"
                            showError = true
                        }
                    }
                } label: {
                    Group {
                        if session.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("登録")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.cyan)
                    .cornerRadius(18)
                }
                .disabled(session.isLoading)

                Button {
                    session.goLogin()
                } label: {
                    Text("ログインへ戻る")
                        .font(.footnote)
                        .foregroundColor(.cyan)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .cornerRadius(28)
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.cyan, lineWidth: 2)
            )
            .shadow(radius: 10)

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .alert(errorMessage, isPresented: $showError) {
            Button("OK", role: .cancel) { }
        }
    }
}
