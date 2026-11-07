// Zeichnet das App-Symbol (1024 px PNG): dunkle Kachel mit orangenem Blitz und Tachobogen.
import Cocoa
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1),
           ending: NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1))!.draw(in: bg, angle: -90)
// Tachobogen
let arc = NSBezierPath()
arc.appendArc(withCenter: NSPoint(x: 512, y: 430), radius: 300, startAngle: 200, endAngle: -20, clockwise: true)
arc.lineWidth = 70; arc.lineCapStyle = .round
NSColor(calibratedWhite: 1, alpha: 0.18).setStroke(); arc.stroke()
let hot = NSBezierPath()
hot.appendArc(withCenter: NSPoint(x: 512, y: 430), radius: 300, startAngle: 60, endAngle: -20, clockwise: true)
hot.lineWidth = 70; hot.lineCapStyle = .round
NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.15, alpha: 1).setStroke(); hot.stroke()
// Blitz
let b = NSBezierPath()
b.move(to: NSPoint(x: 560, y: 700)); b.line(to: NSPoint(x: 420, y: 460)); b.line(to: NSPoint(x: 520, y: 460))
b.line(to: NSPoint(x: 464, y: 230)); b.line(to: NSPoint(x: 620, y: 500)); b.line(to: NSPoint(x: 520, y: 500)); b.close()
NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.25, alpha: 1).setFill(); b.fill()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
