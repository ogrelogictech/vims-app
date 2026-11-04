import SwiftUI

// MARK: - 01 Login

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var email = DemoSeed.loginEmail
    @State private var password = DemoSeed.loginPassword
    @State private var errors = FormErrors()
    @State private var busy = false

    var wide = WideLayout()

    var body: some View {
        Group {
            if wide.isWide { wideBody } else { compactBody }
        }
        .background(VC.paper2.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            #if DEBUG
            // -prefill EMAIL -password PW -validate: try that sign-in once (field-specific error test).
            if DebugFlags.validate, store.path.isEmpty, let e = DebugLaunch.value("-prefill") {
                DebugFlags.validate = false; email = e; password = DebugLaunch.value("-password") ?? ""; signIn(); return
            }
            #endif
            if DebugFlags.validate, store.path.isEmpty { DebugFlags.validate = false; email = "jeremy@@example"; password = "abc"; signIn() }
        }
        .onChange(of: store.passwordResets) { _, _ in
            password = ""
            errors.clear()
        }
    }

    /// iPhone and iPad portrait: brand block over the form (the approved design).
    private var compactBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    brand
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40).padding(.bottom, 36).padding(.horizontal, 24)
                        // The blue runs up under the status bar (and into the pull-down overscroll) but
                        // never below the header, whatever the device height or text size.
                        .background(VC.hdr.padding(.top, -1000))
                    form
                        .padding(.horizontal, 18).padding(.vertical, 24)
                        .readableColumn(PadLayout.formWidth, wideMax: PadLayout.formWidth)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: errors.scrollTarget) { _, t in
                guard let t else { return }
                withAnimation { proxy.scrollTo(t, anchor: .center) }
                errors.scrollTarget = nil
            }
        }
    }

    /// iPad landscape: the blue brand panel fills the left half, the form is centered in the right half.
    private var wideBody: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                brand
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(VC.hdr.ignoresSafeArea())
                ScrollViewReader { proxy in
                    ScrollView {
                        form
                            .padding(.horizontal, 28).padding(.vertical, 32)
                            .frame(maxWidth: 520)
                            .frame(maxWidth: .infinity)
                            .containerRelativeFrame(.vertical, alignment: .center) { h, _ in h }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: errors.scrollTarget) { _, t in
                        guard let t else { return }
                        withAnimation { proxy.scrollTo(t, anchor: .center) }
                        errors.scrollTarget = nil
                    }
                }
                .frame(maxWidth: .infinity)
            }
            // Blue behind the status bar across the whole width, so its white text stays readable on the right too.
            .overlay(alignment: .top) {
                VC.hdr.frame(height: g.safeAreaInsets.top).offset(y: -g.safeAreaInsets.top).allowsHitTesting(false)
            }
        }
    }

    private var brand: some View {
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
    }

    private var form: some View {
        VStack(spacing: 0) {
            VTextField(label: "Email", text: $email, placeholder: "you@company.com", keyboard: .emailAddress,
                       contentType: .username, capitalization: .never, kind: .email, fieldID: "email", errors: errors, required: true)
            VSecureField(label: "Password", text: $password, placeholder: "Password", fieldID: "password", errors: errors, required: true)
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
            catch AuthError.noAccount { errors.set("email", AuthError.noAccount.localizedDescription) }   // email field only
            catch { errors.set("password", error.localizedDescription) }                               // wrong password
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
    @State private var agreed = false
    @State private var errors = FormErrors()
    @State private var busy = false

    var body: some View {
        Screen(title: "Create account", actions: [], errors: errors, maxContentWidth: PadLayout.formWidth) {
            SectionLabel(text: "Your details", top: 2)
                .overlay(alignment: .bottomTrailing) { RequiredHint().fixedSize().padding(.bottom, 4) }
            VTextField(label: "Full name", text: $name, placeholder: "Jeremy Heath", contentType: .name, capitalization: .words,
                       kind: .personName, fieldID: "name", errors: errors, required: true)
            VTextField(label: "Company name", text: $company, placeholder: "Vision Property Inspections", contentType: .organizationName,
                       capitalization: .words, kind: .companyName, fieldID: "company", errors: errors, required: true)
            VTextField(label: "Email", text: $email, placeholder: "you@company.com", keyboard: .emailAddress, contentType: .emailAddress,
                       capitalization: .never, kind: .email, fieldID: "email", errors: errors, required: true)
            VSecureField(label: "Password", text: $password, placeholder: "At least 8 characters", contentType: .newPassword,
                         fieldID: "password", errors: errors, required: true)
            VSecureField(label: "Confirm password", text: $confirm, placeholder: "Re-enter your password", contentType: .newPassword,
                         fieldID: "confirm", errors: errors, required: true)
            EULAAgreeCheckbox(agreed: $agreed, errors: errors)
            Button {
                submit()
            } label: {
                if busy { ProgressView().tint(.white) } else { Text("Create account & continue") }
            }
            .buttonStyle(.vPrimary)
            .disabled(busy)
        }
        .onAppear {
            #if DEBUG
            // -prefill EMAIL [-agree]: valid details (EULA test); with -validate the form is submitted once.
            if let e = DebugLaunch.value("-prefill"), store.path.last == .signup {
                name = "Morgan Blake"; company = "Blake Home Inspections"; email = e; password = "blake2026"; confirm = DebugLaunch.value("-confirm") ?? "blake2026"
                agreed = DebugLaunch.has("-agree")
                if DebugFlags.validate || agreed { DebugFlags.validate = false; submit() }
                return
            }
            #endif
            if DebugFlags.validate { DebugFlags.validate = false; name = "Test  User"; email = "test user@x"; password = "short"; confirm = "shorter"; submit() }
        }
    }

    private func submit() {
        let fields: [(id: String, value: String, rule: FieldRule)] = [
            ("name", name, .req(.personName, "Full name")),
            ("company", company, .req(.companyName, "Company name")),
            ("email", email, .req(.email, "Email", custom: { store.repo.user(email: $0) != nil ? "An account with that email already exists" : nil })),
            ("password", password, .req(.password, "Password")),
            ("confirm", confirm, .req(.plain(max: nil), "Confirm password", custom: { $0 == password ? nil : "Passwords don't match" }))
        ]
        let fieldsOK = errors.validate(fields)
        // The account can't be created until the EULA checkbox is ticked (inline error, like the fields).
        if !agreed {
            errors.map[EULAAgreeCheckbox.fieldID] = EULAAgreeCheckbox.errorText
            if fieldsOK { errors.scrollTarget = EULAAgreeCheckbox.fieldID }
        }
        guard fieldsOK, agreed else { return }
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
    /// Set once the device owner has confirmed; only then are the new password fields shown.
    @State private var account: UserAccount?
    @State private var password = ""
    @State private var confirm = ""
    /// Why the device check didn't go through (no screen lock, failed). Cancelling shows nothing.
    @State private var notice: String?
    @State private var errors = FormErrors()
    @State private var busy = false

    var body: some View {
        Screen(title: "Reset password", errors: errors, maxContentWidth: PadLayout.formWidth) {
            if let account {
                Text("Choose a new password for \(account.email).")
                    .font(VFont.ui(14)).foregroundStyle(VC.ink2).lineSpacing(3)
                    .padding(.top, 4).padding(.bottom, 16)
                    .fixedSize(horizontal: false, vertical: true)
                VSecureField(label: "New password", text: $password, placeholder: "At least 8 characters", contentType: .newPassword,
                             fieldID: "password", errors: errors, required: true)
                VSecureField(label: "Confirm password", text: $confirm, placeholder: "Re-enter your password", contentType: .newPassword,
                             fieldID: "confirm", errors: errors, required: true)
                Button {
                    save(account)
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text("Update password") }
                }
                .buttonStyle(.vPrimary)
                .disabled(busy)
            } else {
                Text("Your password is stored on this device. Confirm it's you with your device passcode, then choose a new password.")
                    .font(VFont.ui(14)).foregroundStyle(VC.ink2).lineSpacing(3)
                    .padding(.top, 4).padding(.bottom, 16)
                    .fixedSize(horizontal: false, vertical: true)
                VTextField(label: "Email", text: $email, placeholder: "you@company.com", keyboard: .emailAddress, contentType: .emailAddress,
                           capitalization: .never, kind: .email, fieldID: "email", errors: errors, required: true)
                if let notice {
                    Banner(symbol: "info", text: AttributedString(notice))
                        .padding(.bottom, 14)
                }
                Button {
                    confirmOwner()
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text("Continue") }
                }
                .buttonStyle(.vPrimary)
                .disabled(busy)
            }
        }
        .onAppear {
            if DebugFlags.validate { DebugFlags.validate = false; email = "name@company"; _ = errors.validate([("email", email, .req(.email, "Email"))]) }
        }
    }

    private func confirmOwner() {
        notice = nil
        let rule = FieldRule.req(.email, "Email", custom: { store.repo.user(email: $0) == nil ? "No account for that email on this device." : nil })
        guard errors.validate([("email", email, rule)]), let found = store.repo.user(email: Validator.trimmed(email)) else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        busy = true
        Task {
            let result = await DeviceOwnerCheck.confirm(reason: "Confirm it's you to choose a new password.")
            busy = false
            switch result {
            case .confirmed: account = found
            case .cancelled: break
            case .noScreenLock: notice = "Set a screen lock in your device Settings first, then try again."
            case .failed: notice = "We couldn't confirm it's you. Try again."
            }
        }
    }

    private func save(_ account: UserAccount) {
        let fields: [(id: String, value: String, rule: FieldRule)] = [
            ("password", password, .req(.password, "New password")),
            ("confirm", confirm, .req(.plain(max: nil), "Confirm password", custom: { $0 == password ? nil : "Passwords don't match" }))
        ]
        guard errors.validate(fields) else { return }
        busy = true
        Task {
            do { try await store.resetPassword(userID: account.id, newPassword: password) }
            catch { errors.set("password", "Couldn't save the new password. Try again.") }
            busy = false
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
    @State private var agreed = false
    @State private var errors = FormErrors()
    @State private var busy = false

    var body: some View {
        Screen(title: "Join a company", errors: errors, maxContentWidth: PadLayout.formWidth) {
            Text("Enter the company code your inspection company shared with you. Your account will be linked to their license and billing.")
                .font(VFont.ui(14)).foregroundStyle(VC.ink2).lineSpacing(3)
                .padding(.top, 4).padding(.bottom, 16)
                .fixedSize(horizontal: false, vertical: true)
            VTextField(label: "Full name", text: $name, placeholder: "Your name", contentType: .name, capitalization: .words,
                       kind: .personName, fieldID: "name", errors: errors, required: true)
            VTextField(label: "Email", text: $email, placeholder: "you@email.com", keyboard: .emailAddress, contentType: .emailAddress,
                       capitalization: .never, kind: .email, fieldID: "email", errors: errors, required: true)
            VSecureField(label: "Password", text: $password, placeholder: "At least 8 characters", contentType: .newPassword,
                         fieldID: "password", errors: errors, required: true)
            VTextField(label: "Company code", text: $code, placeholder: "VIS-4827", keyboard: .asciiCapable,
                       capitalization: .characters, mono: true, kind: .joinCode, fieldID: "code", errors: errors, required: true)
            // Inspectors joining a company are bound by the agreement too.
            EULAAgreeCheckbox(agreed: $agreed, errors: errors)
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
        .onAppear {
            #if DEBUG
            // -prefill EMAIL -code CODE [-agree]: valid join details (EULA test); with -validate the form is submitted once.
            if let e = DebugLaunch.value("-prefill"), let c = DebugLaunch.value("-code") {
                name = "Casey Nguyen"; email = e; password = "casey2026"; code = c
                agreed = DebugLaunch.has("-agree")
                if DebugFlags.validate || agreed { DebugFlags.validate = false; submit() }
                return
            }
            #endif
            if DebugFlags.validate { DebugFlags.validate = false; code = "ABC-1234"; email = "me@site"; submit() }
        }
    }

    private func submit() {
        let fields: [(id: String, value: String, rule: FieldRule)] = [
            ("name", name, .req(.personName, "Full name")),
            ("email", email, .req(.email, "Email")),
            ("password", password, .req(.password, "Password")),
            ("code", code, .req(.joinCode, "Company code", custom: { store.repo.company(joinCode: $0) == nil ? "No company uses that code" : nil }))
        ]
        let fieldsOK = errors.validate(fields)
        if !agreed {
            errors.map[EULAAgreeCheckbox.fieldID] = EULAAgreeCheckbox.errorText
            if fieldsOK { errors.scrollTarget = EULAAgreeCheckbox.fieldID }
        }
        guard fieldsOK, agreed else { return }
        busy = true
        Task {
            do { try await store.joinCompany(code: code, name: Validator.trimmed(name), email: Validator.trimmed(email), password: password) }
            catch { errors.set("password", error.localizedDescription) }
            busy = false
        }
    }
}
