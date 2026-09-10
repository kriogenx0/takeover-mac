import SwiftUI
import AuthenticationServices

struct AccountView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var account: AccountManager

    @State private var isRegister = false
    @State private var login = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(isRegister ? "Create Account" : "Sign In")
                .font(.title2).fontWeight(.semibold)

            Text(isRegister
                 ? "Create a free account to sync this Mac's setup and restore it anywhere."
                 : "Sign in to sync this Mac's setup and restore it on another Mac.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                if isRegister {
                    field("Username", text: $username, placeholder: "e.g. alex")
                    field("Email", text: $email, placeholder: "you@example.com")
                } else {
                    field("Email or username", text: $login, placeholder: "you@example.com")
                }
                field("Password", text: $password, placeholder: "••••••••", secure: true)
            }

            if let err = account.authError {
                Text(err).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Button("Cancel") { isPresented = false }.buttonStyle(.bordered)
                Spacer()
                if account.isLoadingAuth { ProgressView().scaleEffect(0.8) }
                Button(isRegister ? "Create Account" : "Sign In") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(submitDisabled || account.isLoadingAuth)
            }

            Button(isRegister ? "Already have an account? Sign In" : "New here? Create Account") {
                isRegister.toggle()
                account.authError = nil
            }
            .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)

            HStack {
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                Text("or").font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            }

            SignInWithAppleButton(.signIn, onRequest: { req in
                req.requestedScopes = [.email, .fullName]
            }, onCompletion: { result in
                guard case .success(let auth) = result,
                      let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = cred.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8)
                else { return }
                Task {
                    await account.loginWithApple(idToken: idToken, email: cred.email)
                    if account.authError == nil { isPresented = false }
                }
            })
            .signInWithAppleButtonStyle(.black)
            .frame(height: 32)
        }
        .padding(30)
        .frame(width: 380)
    }

    private var submitDisabled: Bool {
        isRegister
            ? username.isEmpty || email.isEmpty || password.isEmpty
            : login.isEmpty || password.isEmpty
    }

    private func submit() async {
        if isRegister {
            await account.register(email: email, password: password, username: username)
        } else {
            await account.login(login: login, password: password)
        }
        if account.authError == nil { isPresented = false }
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, placeholder: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if secure {
                SecureField(placeholder, text: text).textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
            }
        }
    }
}
