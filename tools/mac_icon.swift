// Lager app-ikonet til Mac (App/Mac.xcassets/AppIcon.appiconset) fra ikonet til iPhone og iPad
// (App/Mobil.xcassets/AppIcon.appiconset/icon-1024.png, laget av tools/make_icons.py): den avrundede formen til
// Mac-ikonene (824 av 1024 punkter, hjørner 185) med luft rundt og en svak skygge, i alle størrelsene macOS bruker.
//
//     swift tools/mac_icon.swift        (fra roten av repoet; bare det som følger med macOS)
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("App/Mobil.xcassets/AppIcon.appiconset/icon-1024.png")
let assets = root.appendingPathComponent("App/Mac.xcassets")
let folder = assets.appendingPathComponent("AppIcon.appiconset")

guard let data = try? Data(contentsOf: source), let rep = NSBitmapImageRep(data: data), let art = rep.cgImage else {
    FileHandle.standardError.write("fant ikke \(source.path)\n".data(using: .utf8)!)
    exit(1)
}

/// Ikonet i [pixels] × [pixels], med formen og skyggen skalert ned fra 1024.
func icon(_ pixels: Int) -> Data {
    let scale = CGFloat(pixels) / 1024
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let body = CGRect(x: 100, y: 100, width: 824, height: 824).applying(CGAffineTransform(scaleX: scale, y: scale))
    let shape = CGPath(roundedRect: body, cornerWidth: 185 * scale, cornerHeight: 185 * scale, transform: nil)
    // skyggen under (litt ned, som Apple sin mal)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 28 * scale,
                      color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()
    // bildet fra iPhone-ikonet inni formen
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.draw(art, in: body)
    context.restoreGState()
    let out = NSBitmapImageRep(cgImage: context.makeImage()!)
    return out.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: folder)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = "icon-\(points)\(factor == 2 ? "@2x" : "").png"
        try icon(points * factor).write(to: folder.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(factor)x", "size": "\(points)x\(points)"])
    }
}
let info = ["author": "xcode", "version": 1] as [String: Any]
func json(_ object: Any, _ url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try (data + "\n".data(using: .utf8)!).write(to: url)
}
try json(["images": images, "info": info], folder.appendingPathComponent("Contents.json"))
try json(["info": info], assets.appendingPathComponent("Contents.json"))
print("Laget \(images.count) bilder i \(folder.path)")
