import AppTrackingTransparency
import Foundation
import GoogleMobileAds
import Observation
import UserMessagingPlatform

/// The free version's ads. Before the first ad it asks for the consent ads need: Google's
/// form where privacy law requires one (EU, UK and similar), then Apple's tracking prompt.
@MainActor
@Observable
final class Ads {
    /// The banner ad unit for this build: Google's test unit in Debug, the real one in Release.
    static let bannerUnitID = Bundle.main.object(forInfoDictionaryKey: "AdMobBannerUnitID") as? String ?? ""

    /// Consent is settled and the ad SDK is running.
    private(set) var isReady = false
    /// Whether the person must be offered a way to change their ad consent (EU, UK).
    private(set) var offersPrivacyChoices = false

    @ObservationIgnored private var isStarting = false

    func start() async {
        guard !isReady, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        let consent = ConsentInformation.shared
        try? await consent.requestConsentInfoUpdate(with: RequestParameters())
        try? await ConsentForm.loadAndPresentIfRequired(from: nil)
        offersPrivacyChoices = consent.privacyOptionsRequirementStatus == .required
        guard consent.canRequestAds else { return }

        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        await MobileAds.shared.start()
        isReady = true
    }

    /// Google's form for changing ad consent later.
    func showPrivacyChoices() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: nil)
    }
}
