// Draws the app icon: a metal desk lamp throwing warm light on a small server (docs/design/States.dc.html).
// swift tools/make-icon.swift Lamp/Assets.xcassets/AppIcon.appiconset /tmp/preview.png
// macOS shows this icon in notifications too. Small sizes drop the detail that would only blur, as the mockup does.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: stops.map { rgb($0.0, $0.1) } as CFArray, locations: stops.map(\.2))!
}

func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
    path.closeSubpath()
    return path
}

enum Detail { case full, medium, small }

/// Draws in the mockup's 240-point space, y down, with the tile from 8 to 232 fitted to the macOS icon grid.
func draw(size: Int) -> CGImage {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let detail: Detail = size >= 128 ? .full : size > 32 ? .medium : .small
    let s = CGFloat(size) / 1024
    c.scaleBy(x: s, y: s)
    c.translateBy(x: 0, y: 1024)
    c.scaleBy(x: 1, y: -1)
    // The icon grid: an 824-point body with a 100-point margin.
    let k: CGFloat = 824 / 224
    let tile = CGRect(x: 8, y: 8, width: 224, height: 224)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 52, cornerHeight: 52, transform: nil)

    c.saveGState()
    c.translateBy(x: 100, y: 100)
    c.scaleBy(x: k, y: k)
    c.translateBy(x: -8, y: -8)

    c.saveGState()
    // Shadows ignore the transform: offset and blur are in pixels, y up.
    c.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 28 * s, color: rgb(0x000000, 0.35))
    c.addPath(tilePath)
    c.setFillColor(rgb(0x1b1c20))
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(tilePath)
    c.clip()
    if detail != .small {
        c.drawLinearGradient(gradient([(0x2a2b30, 1, 0), (0x141518, 1, 1)]), start: CGPoint(x: 120, y: 8), end: CGPoint(x: 120, y: 232), options: [])
    }

    // The light: a cone from the shade down to the desk, and a pool where it lands.
    let cone = polygon([(86, 130), (154, 130), (196, 214), (44, 214)])
    c.saveGState()
    c.addPath(cone)
    c.clip()
    if detail == .full {
        c.drawLinearGradient(gradient([(0xffcf86, 0.55, 0), (0xf2a541, 0, 1)]), start: CGPoint(x: 120, y: 130), end: CGPoint(x: 120, y: 214), options: [])
    } else {
        c.setFillColor(rgb(0xf2a541, detail == .small ? 0.35 : 0.3))
        c.fill(tile)
    }
    c.restoreGState()
    if detail == .full {
        c.saveGState()
        c.translateBy(x: 120, y: 196)
        c.scaleBy(x: 1, y: 16.0 / 78)
        c.drawRadialGradient(gradient([(0xf2a541, 0.35, 0), (0xf2a541, 0, 1)]), startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 78, options: [])
        c.restoreGState()

        // The arm the lamp hangs from.
        c.move(to: CGPoint(x: 120, y: 22))
        c.addLine(to: CGPoint(x: 120, y: 66))
        c.setStrokeColor(rgb(0x6d6e73))
        c.setLineWidth(5)
        c.setLineCap(.round)
        c.strokePath()
    }

    // The metal shade, lit from the front.
    let shade = polygon([(96, 66), (144, 66), (160, 130), (80, 130)])
    c.saveGState()
    c.addPath(shade)
    c.clip()
    if detail == .full {
        c.drawLinearGradient(gradient([(0x8e8f93, 1, 0), (0xe4e4e1, 1, 0.45), (0x9c9da1, 1, 1)]), start: CGPoint(x: 80, y: 0), end: CGPoint(x: 160, y: 0), options: [])
    } else {
        c.setFillColor(rgb(0xd4d4d1))
        c.fill(tile)
    }
    c.restoreGState()
    if detail == .full {
        c.addEllipse(in: CGRect(x: 80, y: 125, width: 80, height: 10))
        c.setFillColor(rgb(0xfff1d6))
        c.fillPath()
    }

    // The machine under the light, with its status light in the same amber.
    if detail != .small {
        let box = CGPath(roundedRect: CGRect(x: 76, y: 168, width: 88, height: 30), cornerWidth: 6, cornerHeight: 6, transform: nil)
        c.saveGState()
        c.addPath(box)
        c.clip()
        if detail == .full {
            c.drawLinearGradient(gradient([(0x3a3b41, 1, 0), (0x25262a, 1, 1)]), start: CGPoint(x: 0, y: 168), end: CGPoint(x: 0, y: 198), options: [])
        } else {
            c.setFillColor(rgb(0x33343a))
            c.fill(tile)
        }
        c.restoreGState()
        let led: CGFloat = detail == .full ? 4 : 6
        c.addEllipse(in: CGRect(x: 92 - led, y: 183 - led, width: led * 2, height: led * 2))
        c.setFillColor(rgb(0xf2a541))
        c.fillPath()
        if detail == .full {
            c.move(to: CGPoint(x: 82, y: 168.5))
            c.addLine(to: CGPoint(x: 158, y: 168.5))
            c.setStrokeColor(rgb(0xffffff, 0.22))
            c.setLineWidth(1)
            c.strokePath()
            c.move(to: CGPoint(x: 106, y: 183))
            c.addLine(to: CGPoint(x: 146, y: 183))
            c.setStrokeColor(rgb(0x55565b))
            c.setLineWidth(3)
            c.setLineCap(.round)
            c.strokePath()
        }
    }

    c.addPath(tilePath)
    c.setStrokeColor(rgb(0xffffff, 0.08))
    c.setLineWidth(1)
    c.strokePath()
    c.restoreGState()
    c.restoreGState()
    return c.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let entries: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for entry in entries {
    let name = "icon_\(entry.points)x\(entry.points)@\(entry.scale)x.png"
    write(draw(size: entry.points * entry.scale), to: output.appendingPathComponent(name))
    images.append(["size": "\(entry.points)x\(entry.points)", "idiom": "mac", "filename": name, "scale": "\(entry.scale)x"])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Contents.json"))
write(draw(size: 1024), to: URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "preview.png"))
