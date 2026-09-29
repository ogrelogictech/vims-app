import SwiftUI

// MARK: - 01 Login

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var email = DemoSeed.loginEmail
    @State private var password = DemoSeed.loginPassword
    @State private var errors = FormErrors()
    @State private var busy = false

    var body: some View {
        ScrollViewReader { proxy in
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
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40).padding(.bottom, 36).padding(.horizontal, 24)
                    // The blue runs up under the status bar (and into the pull-down overscroll) but
                    // never below the header, whatever the device height or text size.
                    .background(VC.hdr.padding(.top, -1000))

                    VStack(spacing: 0) {
                        VTextField(label: "Email", text: $email, placeholder: "you@company.com", keyboard: .emailAddress,
                                   contentType: .username, capitalization: .never, kind: .email, fieldID: "email", errors: errors)
                        VSecureField(label: "Password", text: $password, placeholder: "Password", fieldID: "password", errors: errors)
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
                            IconLabel("Join a company with a code", icon: "join-a-company")
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
            .onChange(of: errors.scrollTarget) { _, t in
                guard let t else { return }
                withAnimation { proxy.scrollTo(t, anchor: .center) }
                errors.scrollTarget = nil
            }
        }
        .background(VC.paper2.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if DebugFlags.validate, store.path.isEmpty { DebugFlags.validate = false; email = "jeremy@@example"; password = "abc"; signIn() }
        }
    }

    private func signIn() {
        let fields: [(id: String, value: String, rule: FieldRule)] = [
            ("email", email, .req(.email, "Email")),
            ("password", password, .req(.password, "Password"))
        ]
        guard errors.validate(fields) else { return }
        busy = true
        Task {
            do { try await store.signIn(email: Validator.trimmed(email), password: password) }
            catch { errors.set("password", error.localizedDescription) }
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
    @State private var confirm = ""
    @State private var errors = FormErrors()
    @State private var busy = false

    var body: some View {
        Screen(title: "Create account", actions: [], errors: errors) {
            SectionLabel(text: "Your details", top: 2)
            VTextField(label: "Full name", text: $name, placeholder: "Jeremy Heath", contentType: .name, capitalization: .words,
                       kind: .personName, fieldID: "name", errors: errors)
            VTextField(label: "Company name", text: $company, placeholder: "Vision Property Inspections", contentType: .organizationName,
                       capitalization: .words, kind: .companyName, fieldID: "company", errors: errors)
            VTextField(label: "Email", text: $email, placeholder: "you@company.com", keyboard: .emailAddress, contentType: .emailAddress,
                       capitalization: .never, kind: .email, fieldID: "email", errors: errors)
            VSecureField(label: "Password", text: $password, placeholder: "At least 8 characters", contentType: .newPassword,
                         fieldID: "password", errors: errors)
            VSecureField(label: "Confirm password", text: $confirm, placeholder: "Re-enter your password", contentType: .newPassword,
                         fieldID: "confirm", errors: errors)
            Button {
                submit()
            } label: {
                if busy { ProgressView().tint(.white) } else { Text("Create account & continue") }
            }
            .buttonStyle(.vPrimary)
            .disabled(busy)
        }
        .onAppear { if DebugFlags.validate { DebugFlags.validate = false; name = "Test  User"; email = "test user@x"; password = "short"; confirm = "shorter"; submit() } }
    }

    private func submit() {
        let fields: [(id: String, value: String, rule: FieldRule)] = [
            ("name", name, .req(.personName, "Full name")),
            ("company", company, .req(.companyName, "Company name")),
            ("email", email, .req(.email, "Email", custom: { store.repo.user(email: $0) != nil ? "An account with that email already exists" : nil })),
            ("password", password, .req(.password, "Password")),
            ("confirm", confirm, .req(.password, "Confirm password", custom: { $0 == password ? nil : "Passwords don't match" }))
        ]
        guard errors.validate(fields) else { return }
        busy = true
        Task {
            do {
                try await store.createAccount(name: Validator.trimmed(name), company: Validator.trimmed(company),
                                              email: Validator.trimmed(email), password: password)
            } catch { errors.set("email", error.localizedDescription) }
            busy = false
        }
    }
}

// MARK: - Forgot password

struct ForgotPasswordView: View {
    @Environment(AppStore.self) private var store
    @State private var email = ""
    @State private var errors = FormErrors()

    var body: some View {
        Screen(title: "Reset password", errors: errors) {
            Text("Enter your email and we'll send a reset link.")
                .font(VFont.ui(14)).foregroundStyle(VC.ink2).lineSpacing(3)
                .padding(.top, 4).padding(.bottom, 16)
            VTextField(label: "Email", text: $email, placeholder: "you@company.com", keyboard: .emailAddress, contentType: .emailAddress,
                       capitalization: .never, kind: .email, fieldID: "email", errors: errors)
            Button("Send reset link") {
                guard errors.validate([("email", email, .req(.email, "Email"))]) else { return }
                Task {
                    do {
                        try await store.auth.requestPasswordReset(email: Validator.trimmed(email))
                        store.toast("Reset link sent")
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        store.back()
                    } catch { errors.set("email", error.localizedDescription) }
                }
            }
            .buttonStyle(.vPrimary)
        }
        .onAppear {
            if DebugFlags.validate { DebugFlags.validate = false; email = "name@company"; _ = errors.validate([("email", email, .req(.email, "Email"))]) }
        }
    }
}

// MARK: - 03 Join a company

struct JoinCompanyView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var errors = FormErrors()
    @State private var busy = false

    var body: some View {
        Screen(title: "Join a company", errors: errors) {
            Text("Enter the company code your inspection company shared with you. Your account will be linked to their license and billing.")
                .font(VFont.ui(14)).foregroundStyle(VC.ink2).lineSpacing(3)
                .padding(.top, 4).padding(.bottom, 16)
                .fixedSize(horizontal: false, vertical: true)
            VTextField(label: "Full name", text: $name, placeholder: "Your name", contentType: .name, capitalization: .words,
                       kind: .personName, fieldID: "name", errors: errors)
            VTextField(label: "Email", text: $email, placeholder: "you@email.com", keyboard: .emailAddress, contentType: .emailAddress,
                       capitalization: .never, kind: .email, fieldID: "email", errors: errors)
            VSecureField(label: "Password", text: $password, placeholder: "At least 8 characters", contentType: .newPassword,
                         fieldID: "password", errors: errors)
            VTextField(label: "Company code", text: $code, placeholder: "VIS-4827", keyboard: .asciiCapable,
                       capitalization: .characters, mono: true, kind: .joinCode, fieldID: "code", errors: errors)
            Button {
                submit()
            } label: {
                if busy { ProgressView().tint(.white) } else { IconLabel("Link my account", icon: "link-my-account") }
            }
            .buttonStyle(.vPrimary)
            .disabled(busy)
            Button("Back to sign in") { store.back() }
                .font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 6)
        }
        .onAppear { if DebugFlags.validate { DebugFlags.validate = false; code = "ABC-1234"; email = "me@site"; submit() } }
    }

    private func submit() {
        let fields: [(id: String, value: String, rule: FieldRule)] = [
            ("name", name, .req(.personName, "Full name")),
            ("email", email, .req(.email, "Email")),
            ("password", password, .req(.password, "Password")),
            ("code", code, .req(.joinCode, "Company code", custom: { store.repo.company(joinCode: $0) == nil ? "No company uses that code" : nil }))
        ]
        guard errors.validate(fields) else { return }
        busy = true
        Task {
            do { try await store.joinCompany(code: code, name: Validator.trimmed(name), email: Validator.trimmed(email), password: password) }
            catch { errors.set("password", error.localizedDescription) }
            busy = false
        }
    }
}
