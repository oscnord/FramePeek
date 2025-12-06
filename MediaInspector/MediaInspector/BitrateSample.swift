//
//  BitrateSample.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation

struct BitrateSample: Identifiable {
    let id = UUID()
    let time: Double        // seconds
    let bitrate: Double     // bits per second
}
