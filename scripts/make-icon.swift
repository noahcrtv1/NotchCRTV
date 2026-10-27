// Gera o ícone 1024×1024: fundo escuro, "ilha" do notch com ponto de status e check. Uso: swift scripts/make-icon.swift out.png
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let bg = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1), NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)])!
        .draw(in: bg, angle: -90)
    // ilha
    let island = NSRect(x: rect.midX - 250, y: inset.maxY - 250, width: 500, height: 150)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: island, xRadius: 75, yRadius: 75).fill()
    NSColor(red: 1.0, green: 0.62, blue: 0.1, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: island.minX + 55, y: island.midY - 28, width: 56, height: 56)).fill()
    NSColor(white: 1, alpha: 0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: island.minX + 145, y: island.midY - 14, width: 240, height: 28), xRadius: 14, yRadius: 14).fill()
    // check
    let cfg = NSImage.SymbolConfiguration(pointSize: 330, weight: .bold)
        .applying(.init(paletteColors: [NSColor(red: 0.2, green: 0.85, blue: 0.45, alpha: 1)]))
    if let sym = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let s = sym.size
        sym.draw(in: NSRect(x: rect.midX - s.width / 2, y: inset.minY + 90, width: s.width, height: s.height))
    }
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
