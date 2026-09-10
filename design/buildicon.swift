import AppKit

// buildicon.swift <source.png> <outDir>
// Rebuilds the app icon: a clean macOS squircle with a blue gradient, with only
// the metal vault (keyed out of the source) composited on top. Sidesteps the
// baked-in glow / drop shadow / opaque backdrop in the source art.

let a = CommandLine.arguments
guard a.count == 3 else { fputs("need <source.png> <outDir>\n", stderr); exit(1) }

guard let img = NSImage(contentsOfFile: a[1]),
      let tiff = img.tiffRepresentation,
      let src0 = NSBitmapImageRep(data: tiff) else { fputs("load failed\n", stderr); exit(1) }
let w = src0.pixelsWide, h = src0.pixelsHigh

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: w*4, bitsPerPixel: 32)!
let g0 = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g0
src0.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
NSGraphicsContext.restoreGraphicsState()
let buf = rep.bitmapData!
@inline(__always) func I(_ x: Int, _ y: Int) -> Int { (y*w + x)*4 }

// 1. Key the background (region grow from the corners, small per-step tolerance).
var sr = 0, sg = 0, sb = 0
for (x,y) in [(0,0),(w-1,0),(0,h-1),(w-1,h-1)] { let p=I(x,y); sr+=Int(buf[p]); sg+=Int(buf[p+1]); sb+=Int(buf[p+2]) }
sr/=4; sg/=4; sb/=4
let stepT2 = 14.0*14.0, absT2 = 170.0*170.0
func d2(_ p: Int,_ q: Int) -> Double { let a=Double(Int(buf[p])-Int(buf[q])), b=Double(Int(buf[p+1])-Int(buf[q+1])), c=Double(Int(buf[p+2])-Int(buf[q+2])); return a*a+b*b+c*c }
func d2s(_ p: Int) -> Double { let a=Double(Int(buf[p])-sr), b=Double(Int(buf[p+1])-sg), c=Double(Int(buf[p+2])-sb); return a*a+b*b+c*c }
var done = [Bool](repeating: false, count: w*h)
var st = [Int]()
for (x,y) in [(0,0),(w-1,0),(0,h-1),(w-1,h-1)] { let c=y*w+x; done[c]=true; buf[c*4+3]=0; st.append(c) }
while let c = st.popLast() {
    let x = c%w, y = c/w, cp = c*4
    for n in [x>0 ? c-1 : -1, x<w-1 ? c+1 : -1, y>0 ? c-w : -1, y<h-1 ? c+w : -1] where n >= 0 && !done[n] {
        if d2(cp, n*4) <= stepT2 && d2s(n*4) <= absT2 { done[n]=true; buf[n*4+3]=0; st.append(n) }
    }
}

// 2. Metal mask = still-opaque and neutral/warm (r+10 >= b). Keep only the
// connected blob reachable from the image centre (the vault assembly).
// The steel carries mild blue reflections (b-r up to ~45); the squircle body and
// glow are strongly blue (b-r well over 90). Split between them.
@inline(__always) func isMetal(_ c: Int) -> Bool {
    let p = c*4
    return buf[p+3] != 0 && Int(buf[p+2]) - Int(buf[p]) < 74
}
var metal = [Bool](repeating: false, count: w*h)
var seed = (h/2)*w + w/2
if !isMetal(seed) {
    outer: for dy in -40...40 { for dx in -40...40 {
        let c = (h/2+dy*4)*w + (w/2+dx*4)
        if c >= 0 && c < w*h && isMetal(c) { seed = c; break outer }
    } }
}
st = [seed]; metal[seed] = true
var mMinX = w, mMinY = h, mMaxX = -1, mMaxY = -1
while let c = st.popLast() {
    let x = c%w, y = c/w
    if x < mMinX { mMinX = x }; if x > mMaxX { mMaxX = x }
    if y < mMinY { mMinY = y }; if y > mMaxY { mMaxY = y }
    for n in [x>0 ? c-1 : -1, x<w-1 ? c+1 : -1, y>0 ? c-w : -1, y<h-1 ? c+w : -1] where n >= 0 && !metal[n] && isMetal(n) {
        metal[n] = true; st.append(n)
    }
}
// Punch the non-metal pixels to transparent so only the vault remains in `rep`.
for c in 0..<(w*h) where !metal[c] { buf[c*4+3] = 0 }
let mW = mMaxX - mMinX + 1, mH = mMaxY - mMinY + 1
fputs("metal blob \(mW)x\(mH) at (\(mMinX),\(mMinY))\n", stderr)
let vault = NSImage(size: NSSize(width: w, height: h)); vault.addRepresentation(rep)

// 3. Compose each size.
func squirclePath(canvas: Double) -> NSBezierPath {
    let body = canvas * 824.0/1024.0
    let inset = (canvas - body)/2.0
    return NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: body, height: body),
                        xRadius: body*0.225, yRadius: body*0.225)
}

func render(_ size: Int) -> NSBitmapImageRep {
    let s = Double(size)
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: size*4, bitsPerPixel: 32)!
    let gc = NSGraphicsContext(bitmapImageRep: out)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
    gc.imageInterpolation = .high
    NSColor.clear.set(); NSRect(x: 0, y: 0, width: s, height: s).fill()

    let path = squirclePath(canvas: s)
    // blue gradient, top -> bottom
    let grad = NSGradient(colorsAndLocations:
        (NSColor(srgbRed: 0.239, green: 0.706, blue: 0.894, alpha: 1), 0.0),
        (NSColor(srgbRed: 0.130, green: 0.502, blue: 0.847, alpha: 1), 0.34),
        (NSColor(srgbRed: 0.043, green: 0.282, blue: 0.596, alpha: 1), 0.68),
        (NSColor(srgbRed: 0.016, green: 0.090, blue: 0.298, alpha: 1), 1.0))!
    grad.draw(in: path, angle: -90)

    path.addClip()
    // soft top gloss
    let gloss = NSGradient(colorsAndLocations:
        (NSColor(white: 1, alpha: 0.30), 0.0),
        (NSColor(white: 1, alpha: 0.0), 1.0))!
    let body = s * 824.0/1024.0, inset = (s - body)/2.0
    gloss.draw(in: NSRect(x: inset, y: inset + body*0.52, width: body, height: body*0.48), angle: -90)

    // vault: preserve the source proportion (~0.9 of the body wide), centred, nudged down a hair
    let targetW = body * 0.90
    let scale = targetW / Double(mW)
    let drawW = Double(mW) * scale, drawH = Double(mH) * scale
    let ox = (s - drawW)/2.0
    let oy = (s - drawH)/2.0 - body*0.015
    vault.draw(in: NSRect(x: ox, y: oy, width: drawW, height: drawH),
               from: NSRect(x: mMinX, y: h - mMaxY - 1, width: mW, height: mH),
               operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return out
}

for (name, px) in [("icon_1024.png",1024),("icon_512.png",512),("icon_256.png",256),
                   ("icon_128.png",128),("icon_64.png",64),("icon_32.png",32),("icon_16.png",16)] {
    let d = render(px).representation(using: .png, properties: [:])!
    try! d.write(to: URL(fileURLWithPath: a[2]).appendingPathComponent(name))
    fputs("wrote \(name)\n", stderr)
}
