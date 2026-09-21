// Maintainer-only macOS asset conversion. Generated JPEGs are committed; app users never run this.
import Foundation
import ImageIO
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("design/source/coastal.avif")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == 1536, image.height == 1024 else {
    fatalError("Approved coastal source cannot be decoded or has unexpected dimensions")
}
func write(_ image: CGImage, _ path: String) {
    let url = root.appendingPathComponent(path)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { fatalError("Cannot create asset") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("Incomplete asset write") }
}
write(image, "ios/LightPlan/Assets.xcassets/hero-coastal.imageset/hero-coastal.jpg")
guard let sunset = image.cropping(to: CGRect(x: 525, y: 75, width: 1011, height: 800)) else { fatalError("Invalid crop") }
write(sunset, "ios/LightPlan/Assets.xcassets/hero-sunset.imageset/hero-sunset.jpg")
print("Generated 1536×1024 home JPEG and 1011×800 plan JPEG from the approved original scene.")

// Vector icon reproduction from design/source/app-icon.svg; no font or external art dependency.
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Icon context") }
context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1, y: -1)
func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 255)/255, CGFloat((hex >> 8) & 255)/255, CGFloat(hex & 255)/255, alpha])!
}
let gradient = CGGradient(colorsSpace: space, colors: [color(0xC4DEF0),color(0xFBE2C2),color(0xD58B53)] as CFArray, locations: [0,0.52,1])!
context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 819.2, y: 1024), options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
context.move(to: CGPoint(x: -40, y: 742)); context.addQuadCurve(to: CGPoint(x: 1064, y: 742), control: CGPoint(x: 512, y: 348)); context.addLine(to: CGPoint(x: 1064, y: 1100)); context.addLine(to: CGPoint(x: -40, y: 1100)); context.closePath()
context.setFillColor(color(0x1D3945)); context.fillPath()
context.move(to: CGPoint(x: 110, y: 742)); context.addQuadCurve(to: CGPoint(x: 914, y: 742), control: CGPoint(x: 512, y: 608)); context.setStrokeColor(color(0xFCF1DF, alpha: 0.4)); context.setLineWidth(16); context.strokePath()
context.saveGState()
let cy = 691.0 + sqrt(381.0 * 381.0 - 364.0 * 364.0)
context.addArc(center: CGPoint(x: 512, y: cy), radius: 381, startAngle: atan2(691-cy,-364), endAngle: atan2(691-cy,364), clockwise: false)
context.setLineWidth(24); context.setLineCap(.round); context.replacePathWithStrokedPath(); context.clip()
let arcGradient = CGGradient(colorsSpace: space, colors: [color(0xA76330),color(0xF9C97C)] as CFArray, locations: [0,1])!
context.drawLinearGradient(arcGradient, start: CGPoint(x: 148,y: 0), end: CGPoint(x: 876,y: 0), options: [.drawsBeforeStartLocation,.drawsAfterEndLocation]); context.restoreGState()
context.setFillColor(color(0xFFF4CE)); context.fillEllipse(in: CGRect(x: 649,y: 271,width: 132,height: 132))
context.setStrokeColor(color(0xFFEFCA)); context.setLineWidth(14); context.setLineCap(.round)
for segment in [(713.0,242.0,713.0,212.0),(807,335,837,335),(657,246,637,226),(778,256,800,233)] {
    context.move(to: CGPoint(x: segment.0,y: segment.1)); context.addLine(to: CGPoint(x: segment.2,y: segment.3))
}
context.strokePath()
guard let icon = context.makeImage(), let output = CGImageDestinationCreateWithURL(root.appendingPathComponent("ios/LightPlan/Assets.xcassets/AppIcon.appiconset/AppIcon.png") as CFURL, "public.png" as CFString, 1, nil) else { fatalError("Icon output") }
CGImageDestinationAddImage(output, icon, nil)
guard CGImageDestinationFinalize(output) else { fatalError("Icon write") }
print("Generated opaque 1024px vector-based AppIcon PNG.")
