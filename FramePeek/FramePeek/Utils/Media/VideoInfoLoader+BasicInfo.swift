import Foundation

struct BasicFileInfo {
    let fileName: String
    let fileSize: String
    let fileSizeBytes: UInt64?
    let containerFormat: String?
    let containerFormatProfile: String?
}

func extractBasicInfo(url: URL) -> BasicFileInfo {
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


