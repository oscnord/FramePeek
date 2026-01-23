import Foundation
import AVFoundation

struct MetadataInfo {
    let creationDate: String?
    let title: String?
    let artist: String?
    let encoder: String?
    let description: String?
}

func formatCreationDate(from asset: AVAsset) async -> String? {
    guard
        let creationItem = try? await asset.load(.creationDate),
        let date = try? await creationItem.load(.dateValue)
    else {
        return nil
    }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}

func extractCommonMetadata(from asset: AVAsset) async -> (
    title: String?,
    artist: String?,
    encoder: String?,
    description: String?
) {
    var title: String?
    var artist: String?
    var encoder: String?
    var description: String?

    guard let commonMetadata = try? await asset.load(.commonMetadata) else {
        return (nil, nil, nil, nil)
    }

    for item in commonMetadata {
        guard let commonKey = item.commonKey?.rawValue,
              let value = try? await item.load(.stringValue) else { continue }

        switch commonKey {
        case "title":
            if title == nil { title = value }
        case "artist":
            if artist == nil { artist = value }
        case "encoder":
            if encoder == nil { encoder = value }
        case "description":
            if description == nil { description = value }
        default:
            break
        }
    }

    return (title, artist, encoder, description)
}

func extractMetadataInfo(asset: AVAsset) async -> MetadataInfo {
    async let creationDate = formatCreationDate(from: asset)
    let commonMetadata = await extractCommonMetadata(from: asset)

    return MetadataInfo(
        creationDate: await creationDate,
        title: commonMetadata.title,
        artist: commonMetadata.artist,
        encoder: commonMetadata.encoder,
        description: commonMetadata.description
    )
}
