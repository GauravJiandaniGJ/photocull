// Renders the app icon (1024x1024 PNG) with CoreGraphics. Run: swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }

// Background: diagonal gradient, deep indigo → teal.
let gradient = CGGradient(colorsSpace: space, colors: [rgb(0.24, 0.20, 0.72), rgb(0.05, 0.62, 0.72)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath { CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil) }

/// A "print": white card with a picture area. Drawn around the origin so it can be rotated.
func drawCard(center: CGPoint, angle: CGFloat, alpha: CGFloat, withPicture: Bool, shadow: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let w: CGFloat = 400, h: CGFloat = 480
    let card = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0, 0, 0, 0.35)) }
    ctx.setFillColor(rgb(1, 1, 1, alpha))
    ctx.addPath(roundedRect(card, radius: 36))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    if withPicture {
        // Picture area (sky), leaving a thicker white band at the bottom.
        let pic = CGRect(x: -w / 2 + 28, y: -h / 2 + 96, width: w - 56, height: h - 124)
        ctx.saveGState()
        ctx.addPath(roundedRect(pic, radius: 20))
        ctx.clip()
        let sky = CGGradient(colorsSpace: space, colors: [rgb(0.55, 0.80, 0.98), rgb(0.86, 0.94, 1.0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: pic.maxY), end: CGPoint(x: 0, y: pic.minY), options: [])
        // Sun
        ctx.setFillColor(rgb(1.0, 0.78, 0.25))
        ctx.fillEllipse(in: CGRect(x: pic.maxX - 130, y: pic.maxY - 130, width: 84, height: 84))
        // Mountains
        ctx.setFillColor(rgb(0.16, 0.55, 0.52))
        ctx.move(to: CGPoint(x: pic.minX, y: pic.minY))
        ctx.addLine(to: CGPoint(x: pic.minX + 120, y: pic.minY + 190))
        ctx.addLine(to: CGPoint(x: pic.minX + 215, y: pic.minY + 70))
        ctx.addLine(to: CGPoint(x: pic.minX + 275, y: pic.minY + 150))
        ctx.addLine(to: CGPoint(x: pic.maxX, y: pic.minY))
        ctx.closePath()
        ctx.fillPath()
        ctx.setFillColor(rgb(0.10, 0.42, 0.42))
        ctx.move(to: CGPoint(x: pic.minX + 150, y: pic.minY))
        ctx.addLine(to: CGPoint(x: pic.minX + 270, y: pic.minY + 120))
        ctx.addLine(to: CGPoint(x: pic.maxX, y: pic.minY + 20))
        ctx.addLine(to: CGPoint(x: pic.maxX, y: pic.minY))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

// Two discarded prints behind, the keeper in front.
drawCard(center: CGPoint(x: 400, y: 560), angle: -14, alpha: 0.28, withPicture: false, shadow: false)
drawCard(center: CGPoint(x: 470, y: 545), angle: -6, alpha: 0.5, withPicture: false, shadow: false)
drawCard(center: CGPoint(x: 540, y: 520), angle: 6, alpha: 1, withPicture: true, shadow: true)

// Green check badge on the keeper.
let badgeCenter = CGPoint(x: 760, y: 300)
let badgeRadius: CGFloat = 118
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.3))
ctx.setFillColor(rgb(0.13, 0.72, 0.36))
ctx.fillEllipse(in: CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius, width: badgeRadius * 2, height: badgeRadius * 2))
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setStrokeColor(rgb(1, 1, 1))
ctx.setLineWidth(36)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: badgeCenter.x - 58, y: badgeCenter.y - 4))
ctx.addLine(to: CGPoint(x: badgeCenter.x - 14, y: badgeCenter.y - 48))
ctx.addLine(to: CGPoint(x: badgeCenter.x + 64, y: badgeCenter.y + 44))
ctx.strokePath()

let image = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
