import CoreText
import SwiftUI

enum Retro {
    static let phosphor = Color(red: 0.42, green: 1, blue: 0.56)
    static let dim = phosphor.opacity(0.55)
    static let screen = Color(red: 0.02, green: 0.04, blue: 0.03)
    /// The font's pixels land on whole screen pixels at multiples of this.
    private static let fontStep: CGFloat = 11
    private static let fontName = "DepartureMono-Regular"
    static let small = Font.custom(fontName, fixedSize: fontStep)
    static let body = Font.custom(fontName, fixedSize: fontStep * 2)
    static let title = Font.custom(fontName, fixedSize: fontStep * 3)

    static func registerFont() {
        guard let url = Bundle.main.url(forResource: "DepartureMono-Regular", withExtension: "otf") else {
            NSLog("SpaceWallpaper: the settings font is missing")
            return
        }
        var error: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }
}

struct CRTOverlay: View {
    private static let lineSpacing: CGFloat = 3
    private static let lineOpacity = 0.22
    private static let cornerOpacity = 0.45

    var body: some View {
        Canvas { context, size in
            var lines = Path()
            for y in stride(from: 0, to: size.height, by: Self.lineSpacing) {
                lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
            }
            context.fill(lines, with: .color(.black.opacity(Self.lineOpacity)))
        }
        .overlay(RadialGradient(colors: [.clear, .black.opacity(Self.cornerOpacity)], center: .center, startRadius: 240, endRadius: 620))
        .allowsHitTesting(false)
    }
}
