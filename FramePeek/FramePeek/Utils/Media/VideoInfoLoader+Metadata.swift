//
//  VideoInfoLoader+Metadata.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

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
        let date = creationItem.dateValue
    else {
        return nil
    }
    
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}

func extractCommonMetadata(from asset: AVAsset) -> (
    title: String?,
    artist: String?,
    encoder: String?,
    description: String?
) {
    var title: String?
    var artist: String?
    var encoder: String?
    var description: String?
    
    for item in asset.commonMetadata {
        guard let commonKey = item.commonKey?.rawValue,
              let value = item.stringValue else { continue }
        
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
    let commonMetadata = extractCommonMetadata(from: asset)
    
    return MetadataInfo(
        creationDate: await creationDate,
        title: commonMetadata.title,
        artist: commonMetadata.artist,
        encoder: commonMetadata.encoder,
        description: commonMetadata.description
    )
}


