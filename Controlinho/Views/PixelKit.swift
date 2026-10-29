import SwiftUI

// A small pixel-art UI kit in a sober steampunk style: dark riveted iron, aged brass and
// copper, chunky bevels and hand-drawn pixel icons. Every size is a multiple of `Pixel.unit`
// so all edges line up on the same chunky grid.

enum Pixel {
    /// Size of one "art pixel" in points.
    static let unit: CGFloat = 3
}

// MARK: Palette

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Palette {
    static let ink = Color(hex: 0x0B0A09)
    /// Main text on iron panels.
    static let text = Color(hex: 0xE2CC9C)
    static let textSoft = Color(hex: 0x958369)
    /// Text on copper frames.
    static let textLight = Color(hex: 0xF0DEB4)
    static let brass = Color(hex: 0xC2903C)
    static let iron = Color(hex: 0x312D29)
    static let ironLight = Color(hex: 0x48423C)
    static let ironDark = Color(hex: 0x1F1C19)
    static let copper = Color(hex: 0x553724)
    static let copperLight = Color(hex: 0x7A5034)
    static let copperDark = Color(hex: 0x342217)
    static let oxblood = Color(hex: 0x8A2B21)
    /// Links and actions: the warm glow of a gauge lamp.
    static let accent = Color(hex: 0xECB45A)
    static let yellow = Color(hex: 0xE3BD58)
    static let red = Color(hex: 0xC94B3B)
    static let green = Color(hex: 0x8DBF77)
    static let divider = Color(hex: 0x4A433C)
    static let floor = Color(hex: 0x161412)
    /// Title bars and sheet backgrounds.
    static let bar = Color(hex: 0x110F0D)
}

/// Colors for one pixel surface: its face, top-left highlight, bottom-right shade and content.
struct PixelTone {
    let face: Color
    let light: Color
    let shade: Color
    let content: Color

    /// Dark gunmetal keys and panels.
    static let iron = PixelTone(face: Palette.iron, light: Palette.ironLight, shade: Palette.ironDark, content: Palette.text)
    /// Copper frames and the arrow pad.
    static let copper = PixelTone(face: Palette.copper, light: Palette.copperLight, shade: Palette.copperDark, content: Palette.textLight)
    /// Polished brass for the main keys (OK, Home).
    static let brass = PixelTone(face: Palette.brass, light: Color(hex: 0xE3B866), shade: Color(hex: 0x7B5822), content: Palette.ink)
    static let oxblood = PixelTone(face: Palette.oxblood, light: Color(hex: 0xAE4234), shade: Color(hex: 0x561A13), content: Palette.textLight)
    /// Sunken look for text fields: dark edge top-left, light edge bottom-right.
    static let field = PixelTone(face: Color(hex: 0x1A1715), light: Color(hex: 0x0E0C0B), shade: Color(hex: 0x3B342E), content: Palette.text)
    static let slot = PixelTone(face: Color(hex: 0x29251F), light: Color(hex: 0x3D3730), shade: Color(hex: 0x181512), content: Palette.text)
}

// MARK: Font

extension Font {
    static func pixel(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Pixelify Sans", size: size).weight(weight)
    }
}

extension Text {
    /// Pixel font text. The slight tracking also turns off the font's ligatures,
    /// whose merged "fl"/"fi" glyphs read badly at small sizes.
    func pixelFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Text {
        font(.pixel(size, weight: weight)).tracking(0.4)
    }

    /// Pixel font text in a heavier weight. The font's bold capital C barely opens and reads
    /// as an O ("Oontrolinho"), so each C keeps the regular weight.
    init(pixel string: String, size: CGFloat, weight: Font.Weight) {
        var text = AttributedString(string)
        text.font = .pixel(size, weight: weight)
        var start = text.startIndex
        while let range = text[start...].range(of: "C") {
            text[range].font = .pixel(size)
            start = range.upperBound
        }
        self = Text(text).tracking(0.4)
    }
}

// MARK: Panels

/// Fills a rectangle with its four corner pixels cut off, the basic pixel-art box shape.
private func fillNotched(_ ctx: GraphicsContext, _ rect: CGRect, _ color: Color, notch: CGFloat = Pixel.unit) {
    var path = Path()
    path.addRect(CGRect(x: rect.minX + notch, y: rect.minY, width: rect.width - notch * 2, height: rect.height))
    path.addRect(CGRect(x: rect.minX, y: rect.minY + notch, width: rect.width, height: rect.height - notch * 2))
    ctx.fill(path, with: .color(color))
}

/// A beveled pixel box with a dark outline. With `depth`, it sits on a visible ledge and
/// sinks onto it when `pressed`, like a chunky game button.
struct PixelBox: View {
    var tone: PixelTone
    var depth: CGFloat = 0
    var pressed = false
    /// Brass rivets in the four corners, for panels.
    var rivets = false

    var body: some View {
        Canvas { ctx, size in
            let p = Pixel.unit
            let faceHeight = size.height - depth
            if depth > 0 {
                let ledge = CGRect(x: 0, y: depth, width: size.width, height: faceHeight)
                fillNotched(ctx, ledge, Palette.ink)
                fillNotched(ctx, ledge.insetBy(dx: p, dy: p), tone.shade)
            }
            let offset = pressed ? depth : 0
            let face = CGRect(x: 0, y: offset, width: size.width, height: faceHeight)
            fillNotched(ctx, face, Palette.ink)
            let inner = face.insetBy(dx: p, dy: p)
            fillNotched(ctx, inner, pressed ? tone.shade : tone.face)
            guard inner.width > p * 4, inner.height > p * 4 else { return }
            // Bevel: light along the top and left, shade along the bottom and right.
            let (top, bottom) = pressed ? (tone.shade, tone.light) : (tone.light, tone.shade)
            ctx.fill(Path(CGRect(x: inner.minX + p, y: inner.minY, width: inner.width - p * 2, height: p)), with: .color(top))
            ctx.fill(Path(CGRect(x: inner.minX, y: inner.minY + p, width: p, height: inner.height - p * 2)), with: .color(top))
            ctx.fill(Path(CGRect(x: inner.minX + p, y: inner.maxY - p, width: inner.width - p * 2, height: p)), with: .color(bottom))
            ctx.fill(Path(CGRect(x: inner.maxX - p, y: inner.minY + p, width: p, height: inner.height - p * 2)), with: .color(bottom))
            guard rivets, inner.width > p * 12, inner.height > p * 10 else { return }
            for (x, y) in [(inner.minX + p * 2, inner.minY + p * 2), (inner.maxX - p * 4, inner.minY + p * 2),
                           (inner.minX + p * 2, inner.maxY - p * 4), (inner.maxX - p * 4, inner.maxY - p * 4)] {
                ctx.fill(Path(CGRect(x: x, y: y, width: p * 2, height: p * 2)), with: .color(Color(hex: 0x6E5530)))
                ctx.fill(Path(CGRect(x: x, y: y, width: p, height: p)), with: .color(Color(hex: 0xB8924F)))
            }
        }
    }
}

/// A chunky pixel button that sinks when pressed.
struct PixelButtonStyle: ButtonStyle {
    var tone: PixelTone = .iron
    var depth: CGFloat = Pixel.unit * 2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tone.content)
            .padding(.bottom, depth)
            .offset(y: configuration.isPressed ? depth : 0)
            .background(PixelBox(tone: tone, depth: depth, pressed: configuration.isPressed))
            .contentShape(Rectangle())
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension View {
    /// Places the view on a flat pixel panel.
    func pixelPanel(_ tone: PixelTone = .iron, padding: CGFloat = Pixel.unit * 4, rivets: Bool = true) -> some View {
        self.padding(padding).background(PixelBox(tone: tone, rivets: rivets))
    }
}

// MARK: Background

/// Dark riveted iron plates, drawn on the pixel grid.
struct IronFloor: View {
    var body: some View {
        Canvas { ctx, size in
            let p = Pixel.unit
            let plateWidth = p * 40
            let plateHeight = p * 26
            let faces = [Color(hex: 0x1B1917), Color(hex: 0x1E1B18), Color(hex: 0x191715)]
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                // Stagger every other row by half a plate, like a riveted hull.
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : -plateWidth / 2
                var column = 0
                while x < size.width {
                    let plate = CGRect(x: x, y: y, width: plateWidth, height: plateHeight)
                    ctx.fill(Path(plate), with: .color(faces[(row + column) % faces.count]))
                    // Seams: dark on the bottom/right, faint highlight on the top/left.
                    ctx.fill(Path(CGRect(x: plate.minX, y: plate.minY, width: plate.width, height: p)), with: .color(Color(hex: 0x262320)))
                    ctx.fill(Path(CGRect(x: plate.minX, y: plate.minY, width: p, height: plate.height)), with: .color(Color(hex: 0x262320)))
                    ctx.fill(Path(CGRect(x: plate.minX, y: plate.maxY - p, width: plate.width, height: p)), with: .color(Color(hex: 0x0C0B0A)))
                    ctx.fill(Path(CGRect(x: plate.maxX - p, y: plate.minY, width: p, height: plate.height)), with: .color(Color(hex: 0x0C0B0A)))
                    // Rivets along the top and bottom edges.
                    for rx in stride(from: plate.minX + p * 4, to: plate.maxX - p * 3, by: p * 12) {
                        for ry in [plate.minY + p * 3, plate.maxY - p * 5] {
                            ctx.fill(Path(CGRect(x: rx, y: ry, width: p * 2, height: p * 2)), with: .color(Color(hex: 0x2E2A26)))
                            ctx.fill(Path(CGRect(x: rx, y: ry, width: p, height: p)), with: .color(Color(hex: 0x433D37)))
                        }
                    }
                    x += plateWidth
                    column += 1
                }
                y += plateHeight
                row += 1
            }
        }
        .background(Palette.floor)
        .ignoresSafeArea()
    }
}

// MARK: Icons

/// A tiny bitmap drawn from rows of text: `#` is a filled pixel, anything else is empty.
struct PixelArt {
    let rows: [String]

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }

    var mirrored: PixelArt { PixelArt(rows: rows.map { String($0.reversed()) }) }

    static let power = PixelArt(rows: [
        ".....#.....",
        "..#..#..#..",
        ".#...#...#.",
        "#....#....#",
        "#....#....#",
        "#.........#",
        "#.........#",
        ".#.......#.",
        "..#.....#..",
        "...#####...",
    ])
    static let arrowUp = PixelArt(rows: [
        "...#...",
        "..###..",
        ".#####.",
        "#######",
    ])
    static let home = PixelArt(rows: [
        ".....#.....",
        "....###....",
        "...##.##...",
        "..##...##..",
        ".##.....##.",
        "##.......##",
        ".#.......#.",
        ".#..###..#.",
        ".#..#.#..#.",
        ".#..#.#..#.",
        ".#########.",
    ])
    static let back = PixelArt(rows: [
        "..#........",
        ".##........",
        "########...",
        ".##.....#..",
        "..#......#.",
        ".........#.",
        ".........#.",
        "........#..",
        "..######...",
    ])
    static let menu = PixelArt(rows: [
        "#########",
        ".........",
        ".........",
        "#########",
        ".........",
        ".........",
        "#########",
    ])
    static let source = PixelArt(rows: [
        "###########",
        "#.........#",
        "#.........#",
        "#.........#",
        "#.........#",
        "###########",
        "....###....",
        "..#######..",
    ])
    static let keyboard = PixelArt(rows: [
        "###########",
        "#.........#",
        "#.#.#.#.#.#",
        "#.........#",
        "#.#.#.#.#.#",
        "#.........#",
        "#..#####..#",
        "#.........#",
        "###########",
    ])
    static let info = PixelArt(rows: [
        "..#####..",
        ".#.....#.",
        "#...#...#",
        "#.......#",
        "#...#...#",
        "#...#...#",
        "#...#...#",
        ".#.....#.",
        "..#####..",
    ])
    static let hash = PixelArt(rows: [
        "..#...#..",
        "..#...#..",
        "#########",
        "..#...#..",
        "..#...#..",
        "#########",
        "..#...#..",
        "..#...#..",
    ])
    static let plus = PixelArt(rows: [
        "..###..",
        "..###..",
        "#######",
        "#######",
        "#######",
        "..###..",
        "..###..",
    ])
    static let minus = PixelArt(rows: [
        "#######",
        "#######",
        "#######",
    ])
    static let mute = PixelArt(rows: [
        "...#........",
        "..##........",
        "####..#...#.",
        "#..#...#.#..",
        "#..#....#...",
        "#..#...#.#..",
        "####..#...#.",
        "..##........",
        "...#........",
    ])
    static let guide = PixelArt(rows: [
        "##.#######",
        "..........",
        "##.#######",
        "..........",
        "##.#######",
        "..........",
        "##.#######",
    ])
    static let play = PixelArt(rows: [
        "#......",
        "##.....",
        "###....",
        "####...",
        "#####..",
        "####...",
        "###....",
        "##.....",
        "#......",
    ])
    static let pause = PixelArt(rows: Array(repeating: "###.###", count: 9))
    static let fastForward = PixelArt(rows: [
        "#...#...",
        "##..##..",
        "###.###.",
        "########",
        "###.###.",
        "##..##..",
        "#...#...",
    ])
    static let gear = PixelArt(rows: [
        "....#.#....",
        "..#.###.#..",
        ".#########.",
        "..###.###..",
        ".###...###.",
        "####...####",
        ".###...###.",
        "..###.###..",
        ".#########.",
        "..#.###.#..",
        "....#.#....",
    ])
    static let gem = PixelArt(rows: [
        "..#..",
        ".###.",
        "#####",
        ".###.",
        "..#..",
    ])
    static let check = PixelArt(rows: [
        ".......#",
        "......##",
        "#....##.",
        "##..##..",
        ".####...",
        "..##....",
    ])
    static let warning = PixelArt(rows: [
        "....#....",
        "...###...",
        "...#.#...",
        "..##.##..",
        "..##.##..",
        ".#######.",
        ".###.###.",
        "#########",
    ])
}

/// Draws `PixelArt` in the current foreground style.
struct PixelIcon: View {
    let art: PixelArt
    var scale: CGFloat = Pixel.unit

    init(_ art: PixelArt, scale: CGFloat = Pixel.unit) {
        self.art = art
        self.scale = scale
    }

    var body: some View {
        Canvas { ctx, _ in
            var path = Path()
            for (y, row) in art.rows.enumerated() {
                for (x, char) in row.enumerated() where char == "#" {
                    path.addRect(CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: scale, height: scale))
                }
            }
            ctx.fill(path, with: .foreground)
        }
        .frame(width: CGFloat(art.width) * scale, height: CGFloat(art.height) * scale)
    }
}
