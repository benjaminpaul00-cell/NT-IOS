import GoogleMobileAds
import SwiftUI
import UserMessagingPlatform

@MainActor
final class AdMobService: NSObject, FullScreenContentDelegate {
    static let shared = AdMobService()

    private enum AdUnit {
        #if DEBUG
        static let banner = "ca-app-pub-3940256099942544/2435281174"
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
        #else
        static let banner = "ca-app-pub-2727710137498918/1001311118"
        static let interstitial = "ca-app-pub-2727710137498918/9394631440"
        #endif
    }

    private enum StorageKey {
        static let completedGames = "admob.completed-games"
    }

    static let adsBecameAvailable = Notification.Name("AdMobService.adsBecameAvailable")

    private var interstitialAd: InterstitialAd?
    private var didStartAds = false

    var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    private override init() {
        super.init()
    }

    func start() {
        let parameters = RequestParameters()
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] _ in
            Task { @MainActor in
                do {
                    try await ConsentForm.loadAndPresentIfRequired(from: nil)
                } catch {
                    // A previous valid consent choice can still permit ads after a form error.
                }

                guard ConsentInformation.shared.canRequestAds else { return }
                self?.startAdsIfNeeded()
            }
        }
    }

    func recordCompletedGame() {
        let defaults = UserDefaults.standard
        let completedGames = defaults.integer(forKey: StorageKey.completedGames) + 1
        defaults.set(completedGames, forKey: StorageKey.completedGames)

        guard completedGames.isMultiple(of: 3) else { return }
        presentInterstitialIfReady()
    }

    func presentPrivacyOptions() {
        Task {
            try? await ConsentForm.presentPrivacyOptionsForm(from: nil)
        }
    }

    func loadBanner(_ banner: BannerView) {
        guard canRequestAds else { return }
        banner.adUnitID = AdUnit.banner
        banner.load(Request())
    }

    private func startAdsIfNeeded() {
        guard !didStartAds else { return }
        didStartAds = true
        MobileAds.shared.start()
        NotificationCenter.default.post(name: Self.adsBecameAvailable, object: nil)

        Task {
            await loadInterstitial()
        }
    }

    private func loadInterstitial() async {
        do {
            interstitialAd = try await InterstitialAd.load(
                with: AdUnit.interstitial,
                request: Request()
            )
            interstitialAd?.fullScreenContentDelegate = self
        } catch {
            interstitialAd = nil
        }
    }

    private func presentInterstitialIfReady() {
        guard let interstitialAd else {
            Task {
                await loadInterstitial()
            }
            return
        }

        self.interstitialAd = nil
        interstitialAd.present(from: nil)
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task {
            await loadInterstitial()
        }
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        Task {
            await loadInterstitial()
        }
    }
}

struct AdMobBannerView: View {
    let width: CGFloat

    var body: some View {
        let measuredSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        let backingRatio = max(1, measuredSize.size.width / max(1, width))
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width / backingRatio)
        BannerViewContainer(adSize: adSize)
            .frame(width: width, height: 63)
    }
}

private struct BannerViewContainer: UIViewRepresentable {
    let adSize: AdSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerHostView {
        let host = BannerHostView(adSize: adSize)
        context.coordinator.banner = host.banner
        AdMobService.shared.loadBanner(host.banner)
        return host
    }

    func updateUIView(_ host: BannerHostView, context: Context) {
        guard host.adSize.size != adSize.size else {
            host.setNeedsLayout()
            return
        }
        host.adSize = adSize
        host.banner.adSize = adSize
        AdMobService.shared.loadBanner(host.banner)
        host.setNeedsLayout()
    }

    final class Coordinator {
        weak var banner: BannerView?
        private var observer: NSObjectProtocol?

        init() {
            observer = NotificationCenter.default.addObserver(
                forName: AdMobService.adsBecameAvailable,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let banner = self?.banner else { return }
                    AdMobService.shared.loadBanner(banner)
                }
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

private final class BannerHostView: UIView {
    let banner: BannerView
    var adSize: AdSize

    init(adSize: AdSize) {
        self.adSize = adSize
        banner = BannerView(adSize: adSize)
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .white
        addSubview(banner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let naturalSize = adSize.size
        guard naturalSize.width > 0, naturalSize.height > 0 else { return }

        let factor = min(
            bounds.width / naturalSize.width,
            bounds.height / naturalSize.height
        )
        banner.transform = .identity
        banner.bounds = CGRect(origin: .zero, size: naturalSize)
        banner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        banner.transform = CGAffineTransform(scaleX: factor, y: factor)
    }
}
