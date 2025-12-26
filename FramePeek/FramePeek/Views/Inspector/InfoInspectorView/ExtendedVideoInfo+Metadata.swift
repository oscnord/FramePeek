//
//  ExtendedVideoInfo+Metadata.swift
//  FramePeek
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
