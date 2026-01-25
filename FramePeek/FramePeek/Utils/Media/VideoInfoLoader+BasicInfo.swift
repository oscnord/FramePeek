import Foundation

public struct BasicFileInfo {
    public let fileName: String
    public let fileSize: String
    public let fileSizeBytes: UInt64?
    public let containerFormat: String?
    public let containerFormatProfile: String?
    
    public init(fileName: String, fileSize: String, fileSizeBytes: UInt64?, containerFormat: String?, containerFormatProfile: String?) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.fileSizeBytes = fileSizeBytes
        self.containerFormat = containerFormat
        self.containerFormatProfile = containerFormatProfile
    }
}

public func extractBasicInfo(url: URL) -> BasicFileInfo {
    let fileName = url.lastPathComponent
    let fileSize = getFileSizeString(for: url)
    let fileSizeBytes = getFileSizeBytes(for: url)
    let containerFormat = detectContainerFormat(url: url)
    let containerFormatProfile = parseContainerFormatProfile(url: url)

    return BasicFileInfo(
        fileName: fileName,
        fileSize: fileSize,
        fileSizeBytes: fileSizeBytes,
        containerFormat: containerFormat,
        containerFormatProfile: containerFormatProfile
    )
}
