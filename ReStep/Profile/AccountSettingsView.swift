import SwiftUI

struct AccountSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: AuthSession

    @State private var userId: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var didLoadInitialValues = false
    @State private var successMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 16) {
                Text("アカウント設定")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(spacing: 6) {
                    Text("現在のログイン情報")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("ユーザーID: \(session.user?.loginId ?? "未取得")")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("メールアドレス: \(session.user?.email ?? "未取得")")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)

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
                    prompt: Text("パスワード再入力")
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                )
                .foregroundColor(colorScheme == .dark ? .white : .primary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                if let successMessage {
                    Text(successMessage)
                        .font(.callout)
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage = session.lastErrorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        successMessage = nil
                        let didUpdate = await session.updateAccount(
                            loginId: userId,
                            email: email,
                            password: password,
                            confirmPassword: confirmPassword
                        )
                        if didUpdate {
                            password = ""
                            confirmPassword = ""
                            successMessage = "変更を保存しました"
                        }
                    }
                } label: {
                    Text("変更を保存")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.cyan)
                        .cornerRadius(18)
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
        .onAppear {
            guard didLoadInitialValues == false else { return }
            guard let user = session.user else { return }
            userId = user.loginId
            email = user.email
            didLoadInitialValues = true
        }
        .onChange(of: session.user?.loginId) { _, newValue in
            guard didLoadInitialValues == false else { return }
            userId = newValue ?? ""
            if newValue != nil {
                didLoadInitialValues = true
            }
        }
        .onChange(of: session.user?.email) { _, newValue in
            guard didLoadInitialValues == false else { return }
            email = newValue ?? ""
            if newValue != nil {
                didLoadInitialValues = true
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
@available(iOS 17, *)
struct AccountSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AccountSettingsView()
                .environmentObject(AuthSession())
        }
        .toolbar(.hidden, for: .tabBar)
    }
}
#endif
