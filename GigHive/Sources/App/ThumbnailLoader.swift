import SwiftUI
import UIKit

// MARK: - ThumbnailLoader
//
// Extracted from GuestGalleryView.swift (was private). Now internal so
// UnifiedVideoListView and any future list views can reference these types
// without duplication. GuestGalleryView was removed in Phase 2 (Step 9).
//
// Thumbnail placeholder rule: AsyncThumbnail renders Color.clear when url is nil,
// matching the original behavior. No crash when DB entries have no thumbnailURL.

final class ThumbnailLoader: ObservableObject {
    @Published var image: UIImage?
    func load(from url: URL, credential: AuthCredential? = nil) {
        guard image == nil else { return }
        var request = URLRequest(url: url)
        credential?.apply(to: &request)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { self.image = img }
        }.resume()
    }
}

struct AsyncThumbnail: View {
    let url: URL?
    var credential: AuthCredential? = nil
    @StateObject private var loader = ThumbnailLoader()
    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: 56, height: 40)
        .cornerRadius(4)
        .onAppear {
            if let url = url { loader.load(from: url, credential: credential) }
        }
    }
}
