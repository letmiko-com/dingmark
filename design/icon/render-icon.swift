// Renders the Dingmark "Ruban" icon to the three 1024x1024 PNGs of the asset
// catalog (light, dark, tinted) with CoreGraphics. The geometry is the one of
// the SVG sources next to this file (grid 1024: band 220 wide, 45 degree fold).
// Run from the repo root:  swift design/icon/render-icon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let outDir = root.appendingPathComponent("Dingmark/Resources/Assets.xcassets/AppIcon.appiconset")

let fold: [CGPoint] = [(556,150),(756,350),(756,600),(556,400)].map { CGPoint(x: $0.0, y: $0.1) }
let band: [CGPoint] = [(336,150),(556,150),(556,790),(446,700),(336,790)].map { CGPoint(x: $0.0, y: $0.1) }

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func render(name: String, background: CGColor?, foldColor: CGColor, bandColor: CGColor) throws {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha: CGImageAlphaInfo = background == nil ? .premultipliedLast : .noneSkipLast
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: alpha.rawValue) else {
        throw NSError(domain: "render", code: 1)
    }
    // SVG coordinates have their origin top-left: flip once.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    if let background {
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    for (points, fill) in [(fold, foldColor), (band, bandColor)] {
        ctx.beginPath()
        ctx.addLines(between: points)
        ctx.closePath()
        ctx.setFillColor(fill)
        ctx.fillPath()
    }
    guard let image = ctx.makeImage() else { throw NSError(domain: "render", code: 2) }
    let url = outDir.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "render", code: 3)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "render", code: 4) }
    print("wrote \(url.path)")
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
// Default appearance: teal ground, white band, deep teal fold. Fully opaque
// (App Store Connect rejects an alpha channel on the primary icon).
try render(name: "AppIcon-light.png", background: color(0x00C7BE), foldColor: color(0x007F7A), bandColor: color(0xFFFFFF))
// Dark appearance: deep green ground, teal band.
try render(name: "AppIcon-dark.png", background: color(0x0A2E2C), foldColor: color(0x007F7A), bandColor: color(0x00C7BE))
// Tinted appearance: grayscale glyph on transparency, the system supplies the
// tinted ground and maps luminance to the user's tint.
try render(name: "AppIcon-tinted.png", background: nil, foldColor: color(0x8C8C8C), bandColor: color(0xFFFFFF))
