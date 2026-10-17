import SwiftUI

// Pixel-styled building blocks for the settings screens, used instead of `Form`
// so they match the remote's iron-and-brass look.

/// A scrollable settings page on the wooden floor.
struct PixelPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(IronFloor())
        .tint(Palette.accent)
    }
}

/// A titled iron panel holding rows, with an optional footnote underneath.
struct PixelSection<Content: View>: View {
    var title: String?
    var footer: String?
    var footerIsWarning = false
    var trailing: AnyView?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || trailing != nil {
                HStack {
                    if let title {
                        Text(title)
                            .pixelFont(16, weight: .bold)
                            .foregroundStyle(Palette.textLight)
                    }
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .pixelPanel(.iron, padding: Pixel.unit * 2)
            if let footer {
                Text(footer)
                    .pixelFont(14)
                    .foregroundStyle(footerIsWarning ? Palette.yellow : Palette.textSoft)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A dotted pixel line between rows.
struct PixelDivider: View {
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: Pixel.unit, height: Pixel.unit)), with: .color(Palette.divider))
                x += Pixel.unit * 2
            }
        }
        .frame(height: Pixel.unit)
        .padding(.horizontal, 8)
    }
}

/// A label and a value.
struct PixelInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).pixelFont(16).foregroundStyle(Palette.text)
            Spacer(minLength: 12)
            Text(value)
                .pixelFont(16)
                .foregroundStyle(Palette.textSoft)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
    }
}

/// Row content for a tappable row: a title and an optional chevron.
struct PixelRowLabel: View {
    let title: String
    var color: Color = Palette.accent
    var chevron = false
    var checked = false

    var body: some View {
        HStack {
            Text(title).pixelFont(16, weight: .semibold).foregroundStyle(color)
            Spacer()
            if checked {
                PixelIcon(.check, scale: 2).foregroundStyle(Palette.accent)
            }
            if chevron {
                PixelIcon(PixelArt.arrowUp, scale: 2)
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(Palette.textSoft)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Highlights a row while it's pressed.
struct PixelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.ironLight : .clear)
    }
}

/// A tappable row.
struct PixelActionRow: View {
    let title: String
    var color: Color = Palette.accent
    var checked = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            PixelRowLabel(title: title, color: isEnabled ? color : Palette.textSoft.opacity(0.6), checked: checked)
        }
        .buttonStyle(PixelRowButtonStyle())
    }
}

/// A row that pushes another screen.
struct PixelLinkRow<Destination: View>: View {
    let title: String
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink { destination } label: {
            PixelRowLabel(title: title, color: Palette.text, chevron: true)
        }
        .buttonStyle(PixelRowButtonStyle())
    }
}

/// A text field sunk into the panel like an inventory slot.
struct PixelFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.pixel(17))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(PixelBox(tone: .field))
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .environment(\.colorScheme, .dark)
    }
}

/// A button in a pixel title bar.
struct PixelBarAction {
    let title: String
    var primary = false
    var enabled = true
    let action: () -> Void
}

/// The title bar used instead of the system navigation bar, whose glass buttons and
/// fonts don't fit the pixel style.
struct PixelTopBar: View {
    let title: String
    var leading: PixelBarAction?
    var trailing: PixelBarAction?

    var body: some View {
        ZStack {
            Text(title)
                .pixelFont(19, weight: .bold)
                .foregroundStyle(Palette.textLight)
                .lineLimit(1)
                .padding(.horizontal, 90)
            HStack {
                if let leading { button(leading) }
                Spacer()
                if let trailing { button(trailing) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 54)
        .background(Palette.bar.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.ink).frame(height: Pixel.unit)
        }
    }

    private func button(_ item: PixelBarAction) -> some View {
        Button(action: item.action) {
            Text(item.title)
                .pixelFont(16, weight: .bold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(PixelButtonStyle(tone: item.primary ? .brass : .iron, depth: Pixel.unit))
        .disabled(!item.enabled)
        .opacity(item.enabled ? 1 : 0.5)
    }
}

extension View {
    /// Replaces the system navigation bar with a pixel title bar.
    func pixelScreen(_ title: String, leading: PixelBarAction? = nil, trailing: PixelBarAction? = nil) -> some View {
        toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                PixelTopBar(title: title, leading: leading, trailing: trailing)
            }
    }
}
