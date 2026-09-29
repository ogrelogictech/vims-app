import SwiftUI

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
