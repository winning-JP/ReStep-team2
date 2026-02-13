import SwiftUI

struct LoginView: View {

    @EnvironmentObject private var session: AuthSession
    @Environment(\.colorScheme) private var colorScheme

    @State private var idOrEmail: String = ""
    @State private var password: String = ""
    @State private var showError = false
    @State private var errorMessage = "ログインに失敗しました"

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 16) {
                Text("ログイン")
                    .font(.title2)
                    .fontWeight(.semibold)

                TextField(
                    "",
                    text: $idOrEmail,
                    prompt: Text("ユーザーID / メールアドレス")
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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

                Button {
                    Task {
                        let ok = await session.login(userIdOrEmail: idOrEmail, password: password)
                        if !ok {
                            errorMessage = session.lastErrorMessage ?? "ログインに失敗しました"
                            showError = true
                        }
                    }
                } label: {
                    Group {
                        if session.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("ログイン")
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
                    session.goRegister()
                } label: {
                    Text("新規登録はこちら")
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
