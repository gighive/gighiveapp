import SwiftUI
import UIKit

// MARK: - ThumbnailLoader
//
// Extracted from GuestGalleryView.swift (was private). Now internal so both
// GuestGalleryView (still in use during Phase 1 and 2) and UnifiedVideoListView
// (Phase 2+) can reference these types without duplication.
//
// Thumbnail placeholder rule: AsyncThumbnail renders Color.clear when url is nil,
// matching the original behavior. No crash when DB entries have no thumbnailURL.

final class ThumbnailLoader: ObservableObject {
    @Published var image: UIImage?
    func load(from url: URL) {
        guard image == nil else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { self.image = img }
        }.resume()
    }
}

struct AsyncThumbnail: View {
    let url: URL?
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
            if let url = url { loader.load(from: url) }
        }
    }
}
