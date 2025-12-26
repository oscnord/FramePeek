//
//  QuickSummaryCard.swift
//  FramePeek
//

import SwiftUI

struct QuickSummaryCard: View {
    let info: ExtendedVideoInfo
    
    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                SummaryItem(label: "Resolution", value: info.resolution, icon: "rectangle.on.rectangle")
                SummaryItem(label: "Duration", value: info.durationFormatted, icon: "clock")
                SummaryItem(label: "Codec", value: info.codec, icon: "cpu")
                SummaryItem(label: "FPS", value: info.frameRate, icon: "speedometer")
                SummaryItem(label: "Size", value: info.fileSize, icon: "doc")
                SummaryItem(label: "Bitrate", value: info.overallBitrate, icon: "arrow.up.arrow.down")
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
}

struct SummaryItem: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
    }
}
