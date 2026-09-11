import SwiftUI

/// Shown once, the first time the app is opened signed out: offers signing in
/// (to sync this Mac's setup and restore it elsewhere) or continuing without
/// an account. The account button in the tab bar remains available either way.
struct WelcomeView: View {
    var onSignIn: () -> Void
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.clockwise.icloud")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to Takeover")
                .font(.title2).fontWeight(.semibold)

            Text("Sign in to sync this Mac's Links, Mac Defaults, and Applications, and restore them on another Mac. You can always sign in later from the account button.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            HStack {
                Button("Continue Without Signing In", action: onContinue)
                    .buttonStyle(.bordered)
                Button("Sign In", action: onSignIn)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(30)
        .frame(width: 380)
    }
}
