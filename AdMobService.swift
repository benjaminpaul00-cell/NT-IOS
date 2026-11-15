import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform

@MainActor
final class AdMobService: NSObject, FullScreenContentDelegate {
    static let shared = AdMobService()

    private enum AdUnit {
        #if DEBUG
        static let banner = "ca-app-pub-3940256099942544/2435281174"
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
        #else
        static let banner = "ca-app-pub-2727710137498918/2750305812"
        static let interstitial = "ca-app-pub-2727710137498918/5163257294"
        #endif
    }

    private enum StorageKey {
        static let completedGames = "admob.completed-games"
        static let completedRoundIDs = "admob.completed-round-ids"
        static let pendingInterstitial = "admob.pending-interstitial"
        static let cadenceVersion = "admob.cadence-version"
    }

    static let adsBecameAvailable = Notification.Name("AdMobService.adsBecameAvailable")

    private var interstitialAd: InterstitialAd?
    private var didStartAds = false
    private var isLoadingInterstitial = false
    private var isInterstitialPresentationPending = false
    private var interstitialRetryTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?

    var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    private override init() {
        super.init()
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: StorageKey.cadenceVersion) < 3 {
            defaults.set(0, forKey: StorageKey.completedGames)
            defaults.removeObject(forKey: StorageKey.completedRoundIDs)
            defaults.set(false, forKey: StorageKey.pendingInterstitial)
            defaults.set(3, forKey: StorageKey.cadenceVersion)
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.canRequestAds else { return }
                if self.isInterstitialPresentationPending {
                    self.presentInterstitialIfReady()
                } else if self.interstitialAd == nil {
                    await self.loadInterstitial()
                }
            }
        }
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

    func recordCompletedGame(roundID: String) {
        let defaults = UserDefaults.standard
        var completedRoundIDs = Set(defaults.stringArray(forKey: StorageKey.completedRoundIDs) ?? [])
        guard completedRoundIDs.insert(roundID).inserted else { return }
        if completedRoundIDs.count > 100 {
            completedRoundIDs = [roundID]
        }
        defaults.set(Array(completedRoundIDs), forKey: StorageKey.completedRoundIDs)
        let completedGames = defaults.integer(forKey: StorageKey.completedGames) + 1
        defaults.set(completedGames, forKey: StorageKey.completedGames)

        guard completedGames.isMultiple(of: 3) else { return }
        isInterstitialPresentationPending = true
        defaults.set(true, forKey: StorageKey.pendingInterstitial)
        Task {
            if interstitialAd == nil {
                await loadInterstitial()
            }
            try? await Task.sleep(for: .milliseconds(500))
            presentInterstitialIfReady()
        }
    }

    func presentPendingInterstitialIfNeeded() {
        guard isInterstitialPresentationPending else { return }
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
        isInterstitialPresentationPending = UserDefaults.standard.bool(forKey: StorageKey.pendingInterstitial)
        MobileAds.shared.start()
        NotificationCenter.default.post(name: Self.adsBecameAvailable, object: nil)

        Task {
            await loadInterstitial()
        }
    }

    private func loadInterstitial() async {
        guard !isLoadingInterstitial, interstitialAd == nil else {
            if isInterstitialPresentationPending, interstitialAd != nil {
                presentInterstitialIfReady()
            }
            return
        }
        isLoadingInterstitial = true
        defer { isLoadingInterstitial = false }
        do {
            interstitialAd = try await InterstitialAd.load(
                with: AdUnit.interstitial,
                request: Request()
            )
            interstitialRetryTask?.cancel()
            interstitialRetryTask = nil
            interstitialAd?.fullScreenContentDelegate = self
            if isInterstitialPresentationPending {
                presentInterstitialIfReady()
            }
        } catch {
            interstitialAd = nil
            scheduleInterstitialRetry()
        }
    }

    private func presentInterstitialIfReady() {
        guard let interstitialAd else {
            if canRequestAds {
                Task {
                    await loadInterstitial()
                }
            }
            return
        }

        guard let presenter = topViewController() else { return }

        self.interstitialAd = nil
        interstitialAd.present(from: presenter)
    }

    private func scheduleInterstitialRetry() {
        guard interstitialRetryTask == nil else { return }
        interstitialRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            self.interstitialRetryTask = nil
            await self.loadInterstitial()
        }
    }

    private func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        if let navigation = current as? UINavigationController {
            return navigation.visibleViewController ?? navigation
        }
        if let tabs = current as? UITabBarController {
            return tabs.selectedViewController ?? tabs
        }
        return current
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task {
            await loadInterstitial()
        }
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        isInterstitialPresentationPending = false
        UserDefaults.standard.set(false, forKey: StorageKey.pendingInterstitial)
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        isInterstitialPresentationPending = true
        UserDefaults.standard.set(true, forKey: StorageKey.pendingInterstitial)
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
