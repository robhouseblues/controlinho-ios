import SwiftUI

enum RemoteStyle {
    static let surface = Color.white.opacity(0.08)
    static let surfacePressed = Color.white.opacity(0.18)
    static let stroke = Color.white.opacity(0.08)
}

/// Round/capsule key with a pressed state and a haptic tick.
struct KeyButtonStyle: ButtonStyle {
    var tint: Color = RemoteStyle.surface

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? RemoteStyle.surfacePressed : tint)
                    .overlay(Capsule(style: .continuous).stroke(RemoteStyle.stroke))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// A single labelled remote key.
struct KeyButton: View {
    let symbol: String
    var label: String?
    var size: CGFloat = 64
    var tint: Color = RemoteStyle.surface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: size, height: size)
                .contentShape(Capsule())
        }
        .buttonStyle(KeyButtonStyle(tint: tint))
        .accessibilityLabel(label ?? symbol)
    }
}

/// Vertical +/- rocker used for volume and channel. Holding a side repeats.
struct Rocker: View {
    let title: String
    let upSymbol: String
    let downSymbol: String
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            rockerHalf(upSymbol, label: "\(title) up", action: onUp)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            rockerHalf(downSymbol, label: "\(title) down", action: onDown)
        }
        .frame(width: 72)
        .background(
            Capsule(style: .continuous)
                .fill(RemoteStyle.surface)
                .overlay(Capsule(style: .continuous).stroke(RemoteStyle.stroke))
        )
    }

    private func rockerHalf(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 72, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(RockerHalfStyle())
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }
}

private struct RockerHalfStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.accentColor : .white)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// Circular directional pad with an OK button in the middle.
struct DPad: View {
    let onKey: (TVKey) -> Void
    private let diameter: CGFloat = 250

    var body: some View {
        ZStack {
            Circle()
                .fill(RemoteStyle.surface)
                .overlay(Circle().stroke(RemoteStyle.stroke))

            arrow("chevron.up", .up).offset(y: -diameter * 0.36)
            arrow("chevron.down", .down).offset(y: diameter * 0.36)
            arrow("chevron.left", .left).offset(x: -diameter * 0.36)
            arrow("chevron.right", .right).offset(x: diameter * 0.36)

            Button { onKey(.enter) } label: {
                Text("OK")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(width: diameter * 0.4, height: diameter * 0.4)
                    .contentShape(Circle())
            }
            .buttonStyle(KeyButtonStyle(tint: Color.white.opacity(0.12)))
            .accessibilityLabel("OK")
        }
        .frame(width: diameter, height: diameter)
    }

    private func arrow(_ symbol: String, _ key: TVKey) -> some View {
        Button { onKey(key) } label: {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 70, height: 70)
                .contentShape(Rectangle())
        }
        .buttonStyle(RockerHalfStyle())
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(String(describing: key))
    }
}
