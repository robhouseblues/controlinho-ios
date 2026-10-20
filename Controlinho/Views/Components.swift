import SwiftUI

/// A single square remote key with a pixel icon.
struct KeyButton: View {
    let art: PixelArt
    let label: String
    var size: CGFloat = 56
    var tone: PixelTone = .iron
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PixelIcon(art)
                .frame(width: size, height: size)
        }
        .buttonStyle(PixelButtonStyle(tone: tone))
        .accessibilityLabel(label)
    }
}

/// Vertical +/- rocker used for volume and channel. Holding a side repeats.
struct Rocker: View {
    let title: String
    let up: PixelArt
    let down: PixelArt
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        VStack(spacing: Pixel.unit * 2) {
            half(up, label: "\(title) up", action: onUp)
            Text(title)
                .pixelFont(18)
                .foregroundStyle(Palette.textLight)
            half(down, label: "\(title) down", action: onDown)
        }
        .pixelPanel(.copper, padding: Pixel.unit * 3)
    }

    private func half(_ art: PixelArt, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PixelIcon(art).frame(width: 52, height: 44)
        }
        .buttonStyle(PixelButtonStyle(tone: .iron))
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }
}

/// Cross-shaped directional pad with an OK key in the middle, like a game controller.
struct DPad: View {
    var cell: CGFloat = 64
    let onKey: (TVKey) -> Void

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Color.clear.frame(width: cell, height: cell)
                arrow(.up, rotation: 0)
                Color.clear.frame(width: cell, height: cell)
            }
            GridRow {
                arrow(.left, rotation: -90)
                Button { onKey(.enter) } label: {
                    Text("OK")
                        .font(.pixel(22, weight: .bold))
                        .frame(width: cell, height: cell - Pixel.unit * 2)
                }
                .buttonStyle(PixelButtonStyle(tone: .brass))
                .accessibilityLabel("OK")
                arrow(.right, rotation: 90)
            }
            GridRow {
                Color.clear.frame(width: cell, height: cell)
                arrow(.down, rotation: 180)
                Color.clear.frame(width: cell, height: cell)
            }
        }
    }

    private func arrow(_ key: TVKey, rotation: Double) -> some View {
        Button { onKey(key) } label: {
            PixelIcon(.arrowUp, scale: Pixel.unit + 1)
                .rotationEffect(.degrees(rotation))
                .frame(width: cell, height: cell - Pixel.unit * 2)
        }
        .buttonStyle(PixelButtonStyle(tone: .copper))
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(String(describing: key))
    }
}
