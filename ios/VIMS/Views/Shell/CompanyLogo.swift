import SwiftUI
import UIKit

/// The company's uploaded logo on a white tile, or an initials badge on the brand gradient.
/// Used wherever the company identity shows (company profile, settings, side menu, report).
struct CompanyLogoBadge: View {
    @Environment(AppStore.self) private var store
    var size: CGFloat = 48
    var radius: CGFloat? = nil

    var body: some View {
        let r = radius ?? size * 0.22
        Group {
            if let img = store.companyLogoImage() {
                Image(uiImage: img).resizable().scaledToFit()
                    .padding(size * 0.1)
                    .frame(width: size, height: size)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(VC.line, lineWidth: 1))
            } else {
                Text(Fmt.initials(store.company.name.isEmpty ? (store.session?.name ?? "") : store.company.name))
                    .font(VFont.display(size * 0.34, .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(LinearGradient(colors: [VC.brandBright, VC.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            }
        }
        // Re-render when the logo file changes.
        .id(store.company.logoFile ?? "initials-\(store.company.name)")
        .accessibilityLabel("\(store.company.name) logo")
    }
}

/// A person's own profile photo, or their initials on the brand gradient. Never the company logo.
struct UserAvatar: View {
    @Environment(AppStore.self) private var store
    let userID: UUID?
    let name: String
    var size: CGFloat = 44
    var radius: CGFloat? = nil

    var body: some View {
        let r = radius ?? size / 2
        // Reading currentUser's photoFile keeps the signed-in user's avatar live after a change.
        let key = userID == store.currentUser?.id ? (store.currentUser?.photoFile ?? "none") : (userID?.uuidString ?? "none")
        Group {
            if let userID, let img = store.profilePhoto(userID: userID) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
                    .accessibilityLabel("\(name) profile photo")
            } else {
                Avatar(name: name, size: size, radius: r)
            }
        }
        .id(key)
    }
}

/// Take photo / Choose from library / Remove, for the profile photo and the company logo.
/// Without a camera (simulator) "Take photo" says so and opens the photo library instead.
struct PhotoSourceDialog: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let removeTitle: String?
    let onImage: (UIImage) -> Void
    let onRemove: () -> Void
    @State private var showCamera = false
    @State private var showLibrary = false
    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
                Button(hasCamera ? "Take photo" : "Take photo (no camera — opens library)") {
                    if hasCamera { showCamera = true } else { showLibrary = true }
                }
                Button("Choose from library") { showLibrary = true }
                if let removeTitle { Button(removeTitle, role: .destructive) { onRemove() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                if !hasCamera { Text("This device has no camera.") }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in if let img { onImage(img) } }.ignoresSafeArea()
            }
            .sheet(isPresented: $showLibrary) {
                LibraryPicker { img in if let img { onImage(img) } }
                    .padPageSheet()
            }
    }
}

/// "Do you really want to sign out?" confirmation used everywhere sign-out is offered.
struct SignOutConfirmation: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var isPresented: Bool
    var beforeSignOut: () -> Void = {}

    func body(content: Content) -> some View {
        content.alert("Do you really want to sign out?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                beforeSignOut()
                store.signOut()
            }
        } message: {
            Text("Anything not yet synced stays saved on this device.")
        }
    }
}

extension View {
    func photoSourceDialog(isPresented: Binding<Bool>, title: String, removeTitle: String?,
                           onImage: @escaping (UIImage) -> Void, onRemove: @escaping () -> Void) -> some View {
        modifier(PhotoSourceDialog(isPresented: isPresented, title: title, removeTitle: removeTitle, onImage: onImage, onRemove: onRemove))
    }
    func signOutConfirmation(isPresented: Binding<Bool>, beforeSignOut: @escaping () -> Void = {}) -> some View {
        modifier(SignOutConfirmation(isPresented: isPresented, beforeSignOut: beforeSignOut))
    }
}
