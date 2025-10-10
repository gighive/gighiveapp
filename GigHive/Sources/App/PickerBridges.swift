import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// SwiftUI wrapper for PHPickerViewController (iOS 14+)
struct PHPickerView: UIViewControllerRepresentable {
    var selectionHandler: (URL?) -> Void
    var onFileTooLarge: ((String, String) -> Void)? = nil  // (fileSize, maxSize) -> Void
    var onCopyStarted: (() -> Void)? = nil  // Called when file copy from Photos begins
    var onCopyProgress: ((Double) -> Void)? = nil  // Progress 0.0 to 1.0

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos // we only pick videos from Photos here
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerView
        private var progressObservation: NSKeyValueObservation?
        private var progressTimer: Timer?
        
        init(_ parent: PHPickerView) { self.parent = parent }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { parent.selectionHandler(nil); return }
            let typeId = UTType.movie.identifier
            if provider.hasItemConformingToTypeIdentifier(typeId) {
                print("📊 [PHPicker] Getting file size from metadata...")
                
                // Try to get expected file size from metadata
                var expectedSize: Int64 = 0
                provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, error in
                    if let url = item as? URL {
                        expectedSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                        print("📊 [PHPicker] Expected file size: \(ByteCountFormatter.string(fromByteCount: expectedSize, countStyle: .file))")
                    }
                }
                
                // Notify that copy operation is starting
                DispatchQueue.main.async {
                    print("🚀 [PHPicker] Copy operation starting, showing progress indicator")
                    self.parent.onCopyStarted?()
                }
                
                print("🚀 [PHPicker] Calling loadFileRepresentation...")
                let loadProgress = provider.loadFileRepresentation(forTypeIdentifier: typeId) { [weak self] url, _ in
                    guard let self = self else { return }
                    print("✅ [PHPicker] loadFileRepresentation completed")
                    
                    // Cleanup progress observation
                    self.progressObservation?.invalidate()
                    self.progressObservation = nil
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                    print("🧹 [PHPicker] Cleaned up progress observers")
                    
                    guard let url = url else {
                        DispatchQueue.main.async { self.parent.selectionHandler(nil) }
                        return
                    }
                    // Copy to a persistent temp location so the file remains after dismissal
                    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                    do {
                        // Remove if exists
                        try? FileManager.default.removeItem(at: tmp)
                        
                        print("📋 [PHPicker] Copying to persistent temp location...")
                        try FileManager.default.copyItem(at: url, to: tmp)
                        print("✅ [PHPicker] Copy to temp complete")
                        
                        // Set progress to 100%
                        DispatchQueue.main.async {
                            print("💯 [PHPicker] Setting progress to 100%")
                            self.parent.onCopyProgress?(1.0)
                        }
                        // Debug: Log temp path and size (metadata-only, no full file read)
                        if let size = try? tmp.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                            print("📹 PHPicker: Copied video to \(tmp.lastPathComponent), size: \(sizeStr)")
                            
                            // Validate file size against max upload limit
                            if Int64(size) > AppConstants.MAX_UPLOAD_SIZE_BYTES {
                                let maxStr = AppConstants.MAX_UPLOAD_SIZE_FORMATTED
                                print("⚠️ PHPicker: File too large (\(sizeStr)) - exceeds max allowed size (\(maxStr))")
                                DispatchQueue.main.async {
                                    self.parent.onFileTooLarge?(sizeStr, maxStr)
                                    self.parent.selectionHandler(nil)
                                }
                                return
                            }
                        }
                        DispatchQueue.main.async { self.parent.selectionHandler(tmp) }
                    } catch {
                        DispatchQueue.main.async { self.parent.selectionHandler(nil) }
                    }
                }
                
                // Observe Progress object for updates
                print("👀 [PHPicker] Setting up Progress observation...")
                print("📊 [PHPicker] Progress totalUnitCount: \(loadProgress.totalUnitCount) bytes")
                if loadProgress.totalUnitCount > 0 {
                    let sizeStr = ByteCountFormatter.string(fromByteCount: loadProgress.totalUnitCount, countStyle: .file)
                    print("📊 [PHPicker] File size being copied: \(sizeStr)")
                }
                self.progressObservation = loadProgress.observe(\.fractionCompleted, options: [.new]) { progress, change in
                    let fraction = progress.fractionCompleted
                    print("📈 [PHPicker] Progress KVO update: \(Int(fraction * 100))%")
                    DispatchQueue.main.async {
                        self.parent.onCopyProgress?(fraction)
                    }
                }
                
                // Fallback: Start polling timer in case Progress object doesn't update
                DispatchQueue.main.async {
                    print("⏱️ [PHPicker] Starting fallback polling timer (0.1s interval)...")
                    var lastReportedProgress: Double = 0.0
                    self.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                        let currentProgress = loadProgress.fractionCompleted
                        if currentProgress != lastReportedProgress {
                            print("📈 [PHPicker] Polling detected progress change: \(Int(currentProgress * 100))%")
                            lastReportedProgress = currentProgress
                            self.parent.onCopyProgress?(currentProgress)
                        }
                    }
                }
            } else {
                DispatchQueue.main.async { self.parent.selectionHandler(nil) }
            }
        }
    }
}

// SwiftUI wrapper for UIDocumentPickerViewController (Files)
struct DocumentPickerView: UIViewControllerRepresentable {
    var allowedTypes: [UTType]
    var onPick: (URL?) -> Void
    var onFileTooLarge: ((String, String) -> Void)? = nil  // (fileSize, maxSize) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        init(_ parent: DocumentPickerView) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { parent.onPick(nil); return }
            let isAccessed = url.startAccessingSecurityScopedResource()
            defer { if isAccessed { url.stopAccessingSecurityScopedResource() } }
            // Copy to temp to ensure we own a stable file URL
            let ext = url.pathExtension
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            do {
                try? FileManager.default.removeItem(at: tmp)
                try FileManager.default.copyItem(at: url, to: tmp)
                // Debug: Log temp path and size (metadata-only, no full file read)
                if let size = try? tmp.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                    print("📁 DocumentPicker: Copied file to \(tmp.lastPathComponent), size: \(sizeStr)")
                    
                    // Validate file size against max upload limit
                    if Int64(size) > AppConstants.MAX_UPLOAD_SIZE_BYTES {
                        let maxStr = AppConstants.MAX_UPLOAD_SIZE_FORMATTED
                        print("⚠️ DocumentPicker: File too large (\(sizeStr)) - exceeds max allowed size (\(maxStr))")
                        parent.onFileTooLarge?(sizeStr, maxStr)
                        parent.onPick(nil)
                        return
                    }
                }
                parent.onPick(tmp)
            } catch {
                parent.onPick(nil)
            }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onPick(nil)
        }
    }
}
