import Foundation

/// Custom InputStream that builds multipart/form-data body on-the-fly
/// Streams file directly from disk without creating temp files
class MultipartInputStream: InputStream {
    
    // MARK: - Properties
    private let fileURL: URL
    private let boundary: String
    private let formFields: [(name: String, value: String)]
    private let fileFieldName: String
    private let fileName: String
    private let mimeType: String
    
    private var currentPhase: Phase = .header
    private var fileHandle: FileHandle?
    private var headerData: Data?
    private var footerData: Data?
    private var headerOffset = 0
    private var footerOffset = 0
    private var totalBytesRead: Int64 = 0
    private var fileSize: Int64 = 0
    
    private enum Phase {
        case header
        case fileContent
        case footer
        case complete
    }
    
    // MARK: - Initialization
    init(fileURL: URL, boundary: String, formFields: [(String, String)],
         fileFieldName: String, fileName: String, mimeType: String) throws {
        self.fileURL = fileURL
        self.boundary = boundary
        self.formFields = formFields
        self.fileFieldName = fileFieldName
        self.fileName = fileName
        self.mimeType = mimeType
        
        // Get file size
        let attrs = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        self.fileSize = Int64(attrs.fileSize ?? 0)
        
        super.init(data: Data())  // Dummy data, we override read()
        
        // Build header and footer
        self.headerData = buildHeader()
        self.footerData = buildFooter()
    }
    
    // MARK: - InputStream Overrides
    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
        var bytesWritten = 0
        
        while bytesWritten < maxLength && currentPhase != .complete {
            switch currentPhase {
            case .header:
                bytesWritten += readHeader(buffer: buffer.advanced(by: bytesWritten),
                                          maxLength: maxLength - bytesWritten)
            case .fileContent:
                bytesWritten += readFileContent(buffer: buffer.advanced(by: bytesWritten),
                                               maxLength: maxLength - bytesWritten)
            case .footer:
                bytesWritten += readFooter(buffer: buffer.advanced(by: bytesWritten),
                                          maxLength: maxLength - bytesWritten)
            case .complete:
                break
            }
        }
        
        return bytesWritten
    }
    
    override var hasBytesAvailable: Bool {
        return currentPhase != .complete
    }
    
    override var streamStatus: Stream.Status {
        if currentPhase == .complete {
            return .atEnd
        } else if fileHandle != nil {
            return .open
        } else {
            return .notOpen
        }
    }
    
    override var streamError: Error? {
        return nil
    }
    
    private weak var _delegate: StreamDelegate?
    override var delegate: StreamDelegate? {
        get { return _delegate }
        set { _delegate = newValue }
    }
    
    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
        // Not needed for our use case
    }
    
    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
        // Not needed for our use case
    }
    
    override func open() {
        // Open file handle when stream opens
        fileHandle = try? FileHandle(forReadingFrom: fileURL)
    }
    
    override func close() {
        // Close file handle
        if #available(iOS 13.0, *) {
            try? fileHandle?.close()
        } else {
            fileHandle?.closeFile()
        }
        fileHandle = nil
    }
    
    override func property(forKey key: Stream.PropertyKey) -> Any? {
        return nil
    }
    
    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
        return false
    }
    
    // MARK: - Private Methods
    private func buildHeader() -> Data {
        var header = ""
        
        // Add form fields
        for (name, value) in formFields {
            header += "--\(boundary)\r\n"
            header += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            header += "\(value)\r\n"
        }
        
        // Add file field header
        header += "--\(boundary)\r\n"
        header += "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n"
        header += "Content-Type: \(mimeType)\r\n\r\n"
        
        return header.data(using: .utf8)!
    }
    
    private func buildFooter() -> Data {
        let footer = "\r\n--\(boundary)--\r\n"
        return footer.data(using: .utf8)!
    }
    
    private func readHeader(buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
        guard let data = headerData else { return 0 }
        
        let remainingBytes = data.count - headerOffset
        let bytesToCopy = min(remainingBytes, maxLength)
        
        data.copyBytes(to: buffer, from: headerOffset..<(headerOffset + bytesToCopy))
        headerOffset += bytesToCopy
        
        if headerOffset >= data.count {
            currentPhase = .fileContent
        }
        
        return bytesToCopy
    }
    
    private func readFileContent(buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
        guard let handle = fileHandle else {
            currentPhase = .footer
            return 0
        }
        
        let data: Data
        if #available(iOS 13.4, *) {
            guard let chunk = try? handle.read(upToCount: maxLength), !chunk.isEmpty else {
                currentPhase = .footer
                return 0
            }
            data = chunk
        } else {
            let chunk = handle.readData(ofLength: maxLength)
            if chunk.isEmpty {
                currentPhase = .footer
                return 0
            }
            data = chunk
        }
        
        data.copyBytes(to: buffer, count: data.count)
        totalBytesRead += Int64(data.count)
        
        return data.count
    }
    
    private func readFooter(buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
        guard let data = footerData else { return 0 }
        
        let remainingBytes = data.count - footerOffset
        let bytesToCopy = min(remainingBytes, maxLength)
        
        data.copyBytes(to: buffer, from: footerOffset..<(footerOffset + bytesToCopy))
        footerOffset += bytesToCopy
        
        if footerOffset >= data.count {
            currentPhase = .complete
        }
        
        return bytesToCopy
    }
    
    // MARK: - Content Length Calculation
    func contentLength() -> Int64 {
        let headerSize = Int64(headerData?.count ?? 0)
        let footerSize = Int64(footerData?.count ?? 0)
        return headerSize + fileSize + footerSize
    }
}
