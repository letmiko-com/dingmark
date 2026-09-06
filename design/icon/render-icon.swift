// Renders the Dingmark "Ruban" icon to 1024x1024 PNGs (light, dark, tinted)
// with CoreGraphics, from the same geometry as the SVG sources next to this
// file (grid 1024: band 220 wide, 45 degree fold). These PNGs are NOT the app
// icon any more: the app icon is the layered AppIcon.icon package, and these
// renders exist for the places that need a bitmap (web site, store listing,
// social preview). Run from the repo root:  swift design/icon/render-icon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let outDir = root.appendingPathComponent("design/icon/out")

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
// (an icon uploaded to a store or used as a social preview takes no alpha).
try render(name: "icon-light.png", background: color(0x00C7BE), foldColor: color(0x007F7A), bandColor: color(0xFFFFFF))
// Dark appearance: deep green ground, teal band.
try render(name: "icon-dark.png", background: color(0x0A2E2C), foldColor: color(0x007F7A), bandColor: color(0x00C7BE))
// Monochrome glyph on transparency, for a tinted or single-colour context.
try render(name: "icon-mono.png", background: nil, foldColor: color(0x8C8C8C), bandColor: color(0xFFFFFF))
