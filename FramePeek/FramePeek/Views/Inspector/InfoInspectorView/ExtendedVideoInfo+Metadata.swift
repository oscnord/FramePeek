import Foundation
import FramePeekCore

extension ExtendedVideoInfo {
    var hasMetadata: Bool {
        creationDate != nil ||
        metadataTitle != nil ||
        metadataArtist != nil ||
        metadataEncoder != nil ||
        metadataDescription != nil
    }
}
