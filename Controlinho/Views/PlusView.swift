import StoreKit
import SwiftUI

/// What Controlinho Plus adds, and the button to buy it.
struct PlusView: View {
    @Environment(Purchases.self) private var purchases
    @Environment(\.purchase) private var purchase
    @Environment(\.dismiss) private var dismiss

    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            PixelPage {
                VStack(spacing: 6) {
                    Image("Chick")
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .frame(width: 92, height: 76)
                        .accessibilityHidden(true)
                    Text(pixel: "Controlinho Plus", size: 26, weight: .bold)
                        .foregroundStyle(Palette.textLight)
                    Text(purchases.hasPlus ? "Plus is on. Thank you!" : "Pay once, keep it forever.")
                        .pixelFont(16)
                        .foregroundStyle(purchases.hasPlus ? Palette.green : Palette.textSoft)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                PixelSection {
                    perk("Every TV in the house",
                         "Save all your TVs and switch between them with a tap. The Control Center buttons follow the TV you pick.")
                    PixelDivider()
                    perk("No ads", "Just the remote.")
                    if purchases.product?.isFamilyShareable == true {
                        PixelDivider()
                        perk("Shared with your family", "Everyone in your Family Sharing group gets Plus too.")
                    }
                }

                if !purchases.hasPlus {
                    VStack(spacing: 14) {
                        Button {
                            Task { await purchases.buy(using: purchase) }
                        } label: {
                            Group {
                                if purchases.isWorking {
                                    ProgressView().tint(Palette.ink)
                                } else {
                                    Text(pixel: buyTitle, size: 19, weight: .bold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(PixelButtonStyle(tone: .brass))
                        .disabled(purchases.product == nil || purchases.isWorking)
                        .opacity(purchases.product == nil ? 0.5 : 1)

                        Button {
                            Task { await purchases.restore() }
                        } label: {
                            Text(pixel: "Restore purchases", size: 15, weight: .bold)
                                .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(purchases.isWorking)
                    }
                }

                if let note {
                    Text(note)
                        .pixelFont(14)
                        .foregroundStyle(Palette.yellow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .pixelScreen("Plus", trailing: PixelBarAction(title: purchases.hasPlus ? "Done" : "Close", primary: purchases.hasPlus) { dismiss() })
            .task {
                await purchases.loadProduct()
                didLoad = true
            }
        }
    }

    private var buyTitle: String {
        guard let product = purchases.product else { return "Get Plus" }
        return "Get Plus · \(product.displayPrice)"
    }

    private var note: String? {
        if let message = purchases.message { return message }
        if didLoad, purchases.product == nil, !purchases.hasPlus {
            return "Plus isn't available right now. Check your connection and try again later."
        }
        return nil
    }

    private func perk(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PixelIcon(.check, scale: 2)
                .foregroundStyle(Palette.accent)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(pixel: title, size: 17, weight: .semibold).foregroundStyle(Palette.text)
                Text(detail)
                    .pixelFont(14)
                    .foregroundStyle(Palette.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }
}
