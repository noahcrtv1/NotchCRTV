// Ícone de tecla do Stream Deck (Nova demanda · ⌥ Espaço) no estilo da família CRTV:
// fundo preto, objeto com gradiente rosa→roxo e brilho. Uso: swift scripts/make-streamdeck-icon.swift out.png [tamanho]
import AppKit

let px = CGFloat(Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "288") ?? 288)
let s = px / 288 // desenhado em 288 e escalado

let pink = NSColor(red: 1.0, green: 0.24, blue: 0.43, alpha: 1)
let magenta = NSColor(red: 0.86, green: 0.18, blue: 0.62, alpha: 1)
let purple = NSColor(red: 0.55, green: 0.24, blue: 1.0, alpha: 1)
let cyan = NSColor(red: 0.18, green: 0.82, blue: 0.95, alpha: 1)

func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// fundo preto (o Stream Deck arredonda a tecla sozinho)
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: px, height: px).fill()

// brilho difuso atrás do botão
let glow = NSGradient(colors: [magenta.withAlphaComponent(0.45), .clear])!
glow.draw(in: NSBezierPath(ovalIn: R(54, 40, 180, 180)), relativeCenterPosition: .zero)

// ilha dinâmica no topo
let island = NSBezierPath(roundedRect: R(64, 214, 160, 40), xRadius: 20 * s, yRadius: 20 * s)
NSGradient(colors: [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.04, alpha: 1)])!.draw(in: island, angle: -90)
ctx.saveGState()
island.lineWidth = 3 * s
island.addClip()
ctx.restoreGState()
let border = NSBezierPath(roundedRect: R(64, 214, 160, 40).insetBy(dx: 1.5 * s, dy: 1.5 * s), xRadius: 18.5 * s, yRadius: 18.5 * s)
border.lineWidth = 3 * s
// contorno com gradiente: desenha o traço como máscara
ctx.saveGState()
ctx.setLineWidth(3 * s)
ctx.addPath(border.cgPath)
ctx.replacePathWithStrokedPath()
ctx.clip()
NSGradient(colors: [pink, purple, cyan])!.draw(in: R(64, 214, 160, 40), angle: 0)
ctx.restoreGState()
// ponto de status + linha de texto dentro da ilha
NSColor(red: 0.2, green: 0.9, blue: 0.45, alpha: 1).setFill()
NSBezierPath(ovalIn: R(82, 228, 12, 12)).fill()
NSColor(white: 1, alpha: 0.9).setFill()
NSBezierPath(roundedRect: R(104, 230, 76, 8), xRadius: 4 * s, yRadius: 4 * s).fill()
NSColor(white: 1, alpha: 0.35).setFill()
NSBezierPath(roundedRect: R(186, 230, 22, 8), xRadius: 4 * s, yRadius: 4 * s).fill()

// "gota" ligando a ilha ao botão
let drop = NSBezierPath()
drop.move(to: NSPoint(x: 132 * s, y: 214 * s))
drop.curve(to: NSPoint(x: 144 * s, y: 190 * s), controlPoint1: NSPoint(x: 134 * s, y: 204 * s), controlPoint2: NSPoint(x: 140 * s, y: 196 * s))
drop.curve(to: NSPoint(x: 156 * s, y: 214 * s), controlPoint1: NSPoint(x: 148 * s, y: 196 * s), controlPoint2: NSPoint(x: 154 * s, y: 204 * s))
drop.close()
NSGradient(colors: [purple.withAlphaComponent(0.9), magenta])!.draw(in: drop, angle: -90)

// botão "+" com gradiente e volume
let btnRect = R(79, 62, 130, 130)
let btn = NSBezierPath(roundedRect: btnRect, xRadius: 38 * s, yRadius: 38 * s)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 18 * s, color: magenta.withAlphaComponent(0.7).cgColor)
NSGradient(colors: [pink, magenta, purple])!.draw(in: btn, angle: -50)
ctx.restoreGState()
// brilho superior (vidro)
ctx.saveGState()
btn.addClip()
NSGradient(colors: [NSColor(white: 1, alpha: 0.35), NSColor(white: 1, alpha: 0)])!
    .draw(in: NSBezierPath(ovalIn: R(60, 128, 170, 110)), angle: -90)
ctx.restoreGState()
// borda interna sutil
let inner = NSBezierPath(roundedRect: btnRect.insetBy(dx: 1.5 * s, dy: 1.5 * s), xRadius: 36.5 * s, yRadius: 36.5 * s)
inner.lineWidth = 2 * s
NSColor(white: 1, alpha: 0.25).setStroke()
inner.stroke()
// sinal de +
NSColor.white.setFill()
NSBezierPath(roundedRect: R(136, 92, 16, 70), xRadius: 8 * s, yRadius: 8 * s).fill()
NSBezierPath(roundedRect: R(109, 119, 70, 16), xRadius: 8 * s, yRadius: 8 * s).fill()

// tecla "⌥ space"
let label = "⌥  space" as NSString
let font = NSFont.systemFont(ofSize: 21 * s, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 1, alpha: 0.92), .kern: 0.5 * s]
let ts = label.size(withAttributes: attrs)
let keyRect = NSRect(x: (px - ts.width) / 2 - 14 * s, y: 16 * s, width: ts.width + 28 * s, height: 34 * s)
let key = NSBezierPath(roundedRect: keyRect, xRadius: 9 * s, yRadius: 9 * s)
NSColor(white: 0.12, alpha: 1).setFill(); key.fill()
key.lineWidth = 1.5 * s
NSColor(white: 1, alpha: 0.18).setStroke(); key.stroke()
label.draw(at: NSPoint(x: keyRect.midX - ts.width / 2, y: keyRect.midY - ts.height / 2), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
