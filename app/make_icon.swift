// Draws the app icon at 1024x1024 and writes it to the path given as the first argument.
import Cocoa

let out = CommandLine.arguments[1]
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Rounded "board" tile with macOS-style margins
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor(calibratedRed: 0.984, green: 0.980, blue: 0.969, alpha: 1).setFill()
path.fill()
NSGraphicsContext.restoreGraphicsState()

// Dot grid
path.addClip()
NSColor(calibratedRed: 0.86, green: 0.85, blue: 0.81, alpha: 1).setFill()
var y: CGFloat = 140
while y < 924 {
    var x: CGFloat = 140
    while x < 924 {
        NSBezierPath(ovalIn: NSRect(x: x - 6, y: y - 6, width: 12, height: 12)).fill()
        x += 64
    }
    y += 64
}

// Gliding scribble
let stroke = NSBezierPath()
stroke.move(to: NSPoint(x: 230, y: 420))
stroke.curve(to: NSPoint(x: 470, y: 600), controlPoint1: NSPoint(x: 290, y: 640), controlPoint2: NSPoint(x: 400, y: 700))
stroke.curve(to: NSPoint(x: 560, y: 380), controlPoint1: NSPoint(x: 540, y: 500), controlPoint2: NSPoint(x: 470, y: 360))
stroke.curve(to: NSPoint(x: 790, y: 600), controlPoint1: NSPoint(x: 650, y: 400), controlPoint2: NSPoint(x: 720, y: 560))
stroke.lineWidth = 54
stroke.lineCapStyle = .round
stroke.lineJoinStyle = .round
NSColor(calibratedRed: 0.184, green: 0.435, blue: 0.929, alpha: 1).setStroke()
stroke.stroke()

// Red "pen down" dot at the end of the stroke
NSColor(calibratedRed: 0.898, green: 0.282, blue: 0.302, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 790 - 46, y: 600 - 46, width: 92, height: 92)).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
