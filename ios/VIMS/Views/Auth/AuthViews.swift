import SwiftUI

// MARK: - 01 Login

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var email = DemoSeed.loginEmail
    @State private var password = DemoSeed.loginPassword
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Image("VimsLogo")
                        .resizable().scaledToFit()
                        .frame(width: 74, height: 74)
                        .frame(width: 96, height: 96)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 15, y: 12)
                        .padding(.bottom, 16)
                        .accessibilityLabel("VIMS logo")
                    Text("VIMS")
                        .font(VFont.display(30, .heavy))
                        .tracking(0.6)
                        .foregroundStyle(.white)
                    Text("Vision Inspection Management Solutions")
                        .font(VFont.ui(13))
                        .foregroundStyle(VC.hdrSub)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40).padding(.bottom, 36).padding(.horizontal, 24)
                .background(VC.hdr.ignoresSafeArea(edges: .top))

                VStack(spacing: 0) {
                    VTextField(label: "Email", text: $email, placeholder: "you@company.com", keyboard: .emailAddress,
                               contentType: .username, capitalization: .never)
                    VSecureField(label: "Password", text: $password, placeholder: "Password", error: error)
                    Button {
                        signIn()
                    } label: {
                        if busy { ProgressView().tint(.white) } else { Text("Sign in") }
                    }
                    .buttonStyle(.vPrimary)
                    .disabled(busy)

                    Button("Create account") { store.push(.signup) }
                        .buttonStyle(.vGhost).padding(.top, 10)
                    Button { store.push(.join) } label: {
                        Label("Join a company with a code", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.vGhost).padding(.top, 10)
                    Button("Forgot password?") { store.push(.forgot) }
                        .font(VFont.ui(12.5))
                        .foregroundStyle(VC.ink3)
                        .frame(minHeight: 44)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 18).padding(.vertical, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            VStack(spacing: 0) { VC.hdr.frame(height: 320); VC.paper2 }.ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func signIn() {
        error = nil
        busy = true
        Task {
            do { try await store.signIn(email: email, password: password) } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: - 02 Create account

struct SignupView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var company = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        Screen(title: "Create account", actions: []) {
            SectionLabel(text: "Your details", top: 2)
            VTextField(label: "Full name", text: $name, placeholder: "Jeremy Heath", contentType: .name, capitalization: .words)
            VTextField(label: "Company", text: $company, placeholder: "Vision Property Inspections", contentType: .organizationName, capitalization: .words)
            VTextField(label: "Email", text: $email, placeholder: "you@company.com", keyboard: .emailAddress, contentType: .emailAddress, capitalization: .never)
            VSecureField(label: "Password", text: $password, placeholder: "Create a password", contentType: .newPassword, error: error)
            Button("Create account & continue") {
                Task {
                    do { try await store.createAccount(name: name, company: company, email: email, password: password) }
                    catch { self.error = error.localizedDescription }
                }
            }
            .buttonStyle(.vPrimary)
        }
    }
}

// MARK: - Forgot password

struct ForgotPasswordView: View {
    @Environment(AppStore.self) private var store
    @State private var email = ""
    @State private var error: String?

    var body: some View {
        Screen(title: "Reset password") {
            Text("Enter your email and we'll send a reset link.")
                .font(VFont.ui(14)).foregroundStyle(VC.ink2).lineSpacing(3)
                .padding(.top, 4).padding(.bottom, 16)
            VTextField(label: "Email", text: $email, placeholder: "you@company.com", keyboard: .emailAddress, contentType: .emailAddress,
                       capitalization: .never, error: error)
            Button("Send reset link") {
                Task {
                    do {
                        try await store.auth.requestPasswordReset(email: email)
                        store.toast("Reset link sent")
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        store.back()
                    } catch { self.error = error.localizedDescription }
                }
            }
            .buttonStyle(.vPrimary)
        }
    }
}

// MARK: - 03 Join a company

struct JoinCompanyView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var email = ""
    @State private var code = ""
    @State private var error: String?

    var body: some View {
        Screen(title: "Join a company") {
            Text("Enter the company code your inspection company shared with you. Your account will be linked to their license and billing.")
                .font(VFont.ui(14)).foregroundStyle(VC.ink2).lineSpacing(3)
                .padding(.top, 4).padding(.bottom, 16)
                .fixedSize(horizontal: false, vertical: true)
            VTextField(label: "Full name", text: $name, placeholder: "Your name", contentType: .name, capitalization: .words)
            VTextField(label: "Email", text: $email, placeholder: "you@email.com", keyboard: .emailAddress, contentType: .emailAddress, capitalization: .never)
            VTextField(label: "Company code", text: Binding(get: { code }, set: { code = $0.uppercased() }),
                       placeholder: "VIS-4827", capitalization: .characters, mono: true, error: error)
            Button {
                Task {
                    do { try await store.joinCompany(code: code, name: name, email: email) }
                    catch { self.error = error.localizedDescription }
                }
            } label: {
                Label("Link my account", systemImage: "checkmark")
            }
            .buttonStyle(.vPrimary)
            Button("Back to sign in") { store.back() }
                .font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 6)
        }
    }
}
