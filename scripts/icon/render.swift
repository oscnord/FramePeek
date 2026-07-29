import AppKit
import Foundation
import SwiftUI

// render.swift bbox <png>
// render.swift png <in.svg> <out.png> <size> [squircle|square]

/// Apple's macOS icon grid: on a 1024 canvas the body is 824 square with a
/// 185.4 continuous corner radius. Everything scales from those ratios.
let bodyRatio: CGFloat = 824.0 / 1024.0
let radiusRatio: CGFloat = 185.4 / 824.0

func macIconPath(canvas: CGFloat) -> (CGPath, CGRect) {
    let body = canvas * bodyRatio
    let origin = (canvas - body) / 2
    let rect = CGRect(x: origin, y: origin, width: body, height: body)
    let path = Path(roundedRect: rect, cornerRadius: body * radiusRatio, style: .continuous)
    return (path.cgPath, rect)
}

let args = CommandLine.arguments

if args.count >= 3, args[1] == "bbox" {
    guard let img = NSImage(contentsOfFile: args[2]),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }
    let w = cg.width, h = cg.height
    guard let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { exit(1) }
    let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            if ptr[y * bpr + x * bpp + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    print("size \(w)x\(h)  opaque bbox x:\(minX)...\(maxX) y:\(minY)...\(maxY)  inset \(minX)")
    exit(0)
}

guard args.count >= 5, args[1] == "png" else {
    FileHandle.standardError.write("usage: render png <in.svg> <out.png> <size> [mac|square]\n".data(using: .utf8)!)
    exit(2)
}
let size = Int(args[4])!
let shape = args.count >= 6 ? args[5] : "mac"
guard let svg = NSImage(contentsOfFile: args[2]) else {
    FileHandle.standardError.write("cannot load svg\n".data(using: .utf8)!); exit(1)
}
svg.size = NSSize(width: size, height: size)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.interpolationQuality = .high
let full = CGRect(x: 0, y: 0, width: size, height: size)
var drawRect = full
if shape == "mac" {
    let (path, rect) = macIconPath(canvas: CGFloat(size))
    ctx.addPath(path)
    ctx.clip()
    drawRect = rect
}
svg.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let out = rep.representation(using: .png, properties: [:]) else { exit(1) }
try out.write(to: URL(fileURLWithPath: args[3]))
print("\(args[3]) \(size)x\(size) \(shape)")
