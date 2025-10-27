import UIKit
import SwiftUI

enum ShareHelper {
    static func present(_ item: Any) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let root = window.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        root.present(vc, animated: true)
    }
}
