import SwiftUI

@main
struct VIMSApp: App {
    var body: some Scene {
        WindowGroup {
            let url = Bundle.main.url(forResource: "vims-checklists", withExtension: "json")
            let size = url.flatMap { try? Data(contentsOf: $0).count } ?? 0
            Text("VIMS toolchain check — checklist data: \(size) bytes")
        }
    }
}
