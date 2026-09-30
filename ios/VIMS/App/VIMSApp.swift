import SwiftUI
import UIKit

@main
struct VIMSApp: App {
    @State private var store: AppStore?
    @State private var loadError: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistry.registerBundledFonts()
        #if DEBUG
        DebugLaunch.prepareStorage()
        #endif
        do {
            let config = try ChecklistLoader.load()
            let store = AppStore(config: config, eula: try EULADocument.load(), repo: try SwiftDataRepository())
            #if DEBUG
            DebugLaunch.apply(to: store)
            #endif
            _store = State(initialValue: store)
        } catch {
            _loadError = State(initialValue: "VIMS could not start (\(error)).")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    RootView()
                        .environment(store)
                } else {
                    Text(loadError ?? "Loading…").font(VFont.ui(15)).padding()
                }
            }
            .preferredColorScheme(.light)
            .environment(\.locale, Fmt.locale)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .tint(VC.brand)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store?.flushNow() }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ZStack {
            NavigationStack(path: $store.path) {
                Group {
                    if store.session == nil { LoginView() } else { HomeView() }
                }
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
            }

            if store.showSplash, store.session != nil, !store.showVideoSplash, !store.needsEulaAcceptance {
                TrialSplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }

            // New or revised EULA: the user must accept it (or sign out) before using the app.
            if store.session != nil, store.needsEulaAcceptance {
                EULAGateView()
                    .transition(.opacity)
                    .zIndex(15)
            }

            if let msg = store.toastMessage {
                VStack {
                    Spacer()
                    ToastView(message: msg)
                        .padding(.bottom, 26)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(20)
            }

            if store.showVideoSplash {
                VideoSplashView {
                    withAnimation(.easeOut(duration: 0.35)) { store.showVideoSplash = false }
                    // Every sign-in session during the free look starts with the countdown splash.
                    store.presentSplashIfNeeded()
                }
                .transition(.opacity)
                .zIndex(30)
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.toastMessage)
    }

    @ViewBuilder
    private func destination(_ r: Route) -> some View {
        switch r {
        case .signup: SignupView()
        case .forgot: ForgotPasswordView()
        case .join: JoinCompanyView()
        case .wizard(let editing): WizardView(editingID: editing)
        case .sections(let id): SectionsOverviewView(inspectionID: id)
        case .section(let id, let name): SectionEntryView(inspectionID: id, section: name).id("\(id)-\(name)")
        case .photos(let id, let name): PhotosView(inspectionID: id, section: name)
        case .summary(let id): SummaryView(inspectionID: id)
        case .report(let id): ReportView(inspectionID: id)
        case .reportReady(let id): ReportReadyView(inspectionID: id)
        case .settings: SettingsView()
        case .company: CompanyProfileView()
        case .instructions: InstructionsView()
        case .manageChecklist: ManageChecklistView()
        case .editSection(let name): EditSectionView(sectionName: name)
        case .plans: PlansAdminView()
        case .inspectors: InspectorsView()
        case .subscribe: SubscribeView()
        case .subscriptionStarted: SubscriptionStartedView()
        case .billing: BillingView()
        // VIMS platform-owner screens: nobody else can open them (TODO(backend): enforced server-side too).
        case .feedbackAdmin: if store.isPlatformOwner { FeedbackAdminView() } else { OwnerOnlyView() }
        case .reportBcc: if store.isPlatformOwner { ReportBccView() } else { OwnerOnlyView() }
        case .eula: EULAView()
        case .deleteAccount: DeleteAccountView()
        }
    }
}

struct OwnerOnlyView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Screen(title: "Not available", actions: [store.homeAction()]) {
            HintText(text: "This setting is managed by the VIMS platform owner.").padding(.top, 8)
        }
    }
}

struct ToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 9) {
            ProtoIcon("link-my-account", size: 17, lineWidth: 2.4).foregroundStyle(Color(hex: 0x7CE0AF))
            Text(message).font(VFont.ui(13.5, .medium)).foregroundStyle(.white).lineLimit(2)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(VC.ink)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 15, y: 12)
        .padding(.horizontal, 24)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// Keep the edge-swipe back gesture even though the system navigation bar is hidden
// (the app draws the prototype's own blue header).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
