//
//  ExtendedVideoInfo+Metadata.swift
//  MediaInspector
//

import Foundation

extension ExtendedVideoInfo {
    var hasMetadata: Bool {
        creationDate != nil ||
        metadataTitle != nil ||
        metadataArtist != nil ||
        metadataEncoder != nil ||
        metadataDescription != nil
    }
}
