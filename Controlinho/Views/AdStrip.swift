import GoogleMobileAds
import SwiftUI

/// The free version's banner, framed in iron under the remote. It stays collapsed until an
/// ad has loaded, so a failed load doesn't leave an empty box.
struct AdStrip: View {
    @State private var hasAd = false

    var body: some View {
        BannerAd { hasAd = true }
            .frame(width: AdSizeBanner.size.width, height: AdSizeBanner.size.height)
            .frame(maxWidth: .infinity)
            .pixelPanel(.iron, padding: Pixel.unit * 2)
            .padding(.horizontal, 20)
            // Keeps the ad clear of the app shortcuts, so they aren't tapped by mistake.
            .padding(.top, 8)
            .opacity(hasAd ? 1 : 0)
            .allowsHitTesting(hasAd)
            .frame(height: hasAd ? nil : 0, alignment: .top)
            .animation(.easeOut(duration: 0.2), value: hasAd)
    }
}

/// AdMob's standard 320×50 banner. Larger adaptive sizes would squeeze the remote's keys.
private struct BannerAd: UIViewRepresentable {
    let onReceiveAd: () -> Void

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = Ads.bannerUnitID
        banner.delegate = context.coordinator
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onReceiveAd: onReceiveAd)
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        let onReceiveAd: () -> Void

        init(onReceiveAd: @escaping () -> Void) {
            self.onReceiveAd = onReceiveAd
        }

        // A failed refresh keeps showing the previous ad, so only the first load matters.
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onReceiveAd()
        }
    }
}
