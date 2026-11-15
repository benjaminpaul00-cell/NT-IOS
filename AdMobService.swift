import GoogleMobileAds
import SwiftUI
import UIKit
import OSLog
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

    nonisolated static let adsBecameAvailable = Notification.Name("AdMobService.adsBecameAvailable")

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DominoIOS", category: "AdMob")
    private var startupRetryTask: Task<Void, Never>?
    private var isStarting = false
    private var isPresentingInterstitial = false
    private var interstitialAd: InterstitialAd?
    private var sdkReady = false
    private var presentedInterstitialAd: InterstitialAd?
    private var didStartAds = false
    private var isLoadingInterstitial = false
    private var isInterstitialPresentationPending = false
    private var interstitialRetryTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?

    var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    private override convenience init() {
        self.init(defaults: .standard)
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
        if defaults.integer(forKey: StorageKey.cadenceVersion) < 3 {
            defaults.set(0, forKey: StorageKey.completedGames)
            defaults.removeObject(forKey: StorageKey.completedRoundIDs)
            defaults.set(false, forKey: StorageKey.pendingInterstitial)
            defaults.set(3, forKey: StorageKey.cadenceVersion)
        }
        isInterstitialPresentationPending = defaults.bool(forKey: StorageKey.pendingInterstitial)
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.didStartAds { self.start(); return }
                guard self.canRequestAds else { return }
                if self.isInterstitialPresentationPending {
                    self.presentInterstitialIfReady()
                } else if self.interstitialAd == nil {
                    await self.loadInterstitial()
                }
            }
        }
    }

    func start() {
        guard !isStarting, !didStartAds else { return }
        guard let presenter = topViewController(), presenter.viewIfLoaded?.window != nil else {
            scheduleStartupRetry()
            return
        }
        isStarting = true
        let parameters = RequestParameters()
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                defer { self.isStarting = false }
                if let error { self.logger.error("Consent update: \(error.localizedDescription, privacy: .public)") }
                do {
                    try await ConsentForm.loadAndPresentIfRequired(from: presenter)
                } catch {
                    self.logger.error("Consent form: \(error.localizedDescription, privacy: .public)")
                }

                guard ConsentInformation.shared.canRequestAds else {
                    self.logger.notice("Ads blocked by consent state")
                    self.scheduleStartupRetry()
                    return
                }
                self.startAdsIfNeeded()
            }
        }
    }

    private func scheduleStartupRetry() {
        guard startupRetryTask == nil else { return }
        startupRetryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self else { return }
            self.startupRetryTask = nil
            self.start()
        }
    }

    func recordCompletedGame(roundID: String) {
        var completedRoundIDs = Set(defaults.stringArray(forKey: StorageKey.completedRoundIDs) ?? [])
        guard completedRoundIDs.insert(roundID).inserted else { return }
        if completedRoundIDs.count > 100 {
            completedRoundIDs = [roundID]
        }
        defaults.set(Array(completedRoundIDs), forKey: StorageKey.completedRoundIDs)
        let completedGames = defaults.integer(forKey: StorageKey.completedGames) + 1
        defaults.set(completedGames, forKey: StorageKey.completedGames)
        logger.info("Completed rounds: \(completedGames); interstitial due: \(completedGames.isMultiple(of: 3))")

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

    var bannersReady: Bool { sdkReady && canRequestAds }

    func loadBanner(_ banner: BannerView) {
        guard bannersReady else { return }
        banner.adUnitID = AdUnit.banner
        banner.load(Request())
    }

    private func startAdsIfNeeded() {
        guard !didStartAds else { return }
        startupRetryTask?.cancel()
        startupRetryTask = nil
        didStartAds = true
        isInterstitialPresentationPending = defaults.bool(forKey: StorageKey.pendingInterstitial)
        MobileAds.shared.start { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sdkReady = true
                NotificationCenter.default.post(name: Self.adsBecameAvailable, object: nil)
                await self.loadInterstitial()
            }
        }
    }

    private func loadInterstitial() async {
        guard sdkReady, canRequestAds, !isPresentingInterstitial else { return }
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
            logger.error("Interstitial load: \(error.localizedDescription, privacy: .public)")
            interstitialAd = nil
            scheduleInterstitialRetry()
        }
    }

    private func presentInterstitialIfReady() {
        guard isInterstitialPresentationPending, !isPresentingInterstitial, canRequestAds else { return }
        guard let interstitialAd else {
            if canRequestAds {
                Task {
                    await loadInterstitial()
                }
            }
            return
        }

        guard UIApplication.shared.applicationState == .active,
              let presenter = topViewController(),
              presenter.viewIfLoaded?.window != nil,
              !presenter.isBeingPresented, !presenter.isBeingDismissed,
              !(presenter is UIAlertController) else {
            scheduleInterstitialRetry()
            return
        }
        do {
            try interstitialAd.canPresent(from: presenter)
        } catch {
            logger.error("Interstitial not ready: \(error.localizedDescription, privacy: .public)")
            self.interstitialAd = nil
            scheduleInterstitialRetry()
            return
        }
        isPresentingInterstitial = true
        presentedInterstitialAd = interstitialAd
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
        isPresentingInterstitial = false
        presentedInterstitialAd = nil
        Task {
            await loadInterstitial()
        }
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        isInterstitialPresentationPending = false
        defaults.set(false, forKey: StorageKey.pendingInterstitial)
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        isPresentingInterstitial = false
        presentedInterstitialAd = nil
        logger.error("Interstitial presentation: \(error.localizedDescription, privacy: .public)")
        isInterstitialPresentationPending = true
        defaults.set(true, forKey: StorageKey.pendingInterstitial)
        scheduleInterstitialRetry()
    }
}

struct AdMobBannerView: View {
    let width: CGFloat

    var body: some View {
        BannerViewContainer(adSize: AdSizeBanner)
            .frame(width: width, height: AdSizeBanner.size.height)
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
        host.loadIfReady()
        return host
    }

    func updateUIView(_ host: BannerHostView, context: Context) {
        host.loadIfReady()
        guard host.adSize.size != adSize.size else {
            host.setNeedsLayout()
            return
        }
        host.adSize = adSize
        host.banner.adSize = adSize
        host.loadIfReady()
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
                    (banner.superview as? BannerHostView)?.loadIfReady()
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

private final class BannerHostView: UIView, BannerViewDelegate {
    private var nextRetryDate = Date.distantPast
    private var requested = false
    private var retryTask: Task<Void, Never>?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DominoIOS", category: "AdMobBanner")
    let banner: BannerView
    var adSize: AdSize

    init(adSize: AdSize) {
        self.adSize = adSize
        banner = BannerView(adSize: adSize)
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .clear
        banner.delegate = self
        banner.isHidden = true
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

        banner.bounds = CGRect(origin: .zero, size: naturalSize)
        banner.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { loadIfReady() }
        else { retryTask?.cancel(); retryTask = nil }
    }

    func loadIfReady() {
        guard !requested, Date() >= nextRetryDate, window != nil, AdMobService.shared.bannersReady else { return }
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                banner.rootViewController = controller
                break
            }
            responder = current.next
        }
        guard banner.rootViewController != nil else { return }
        requested = true
        AdMobService.shared.loadBanner(banner)
    }

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        bannerView.isHidden = false
        retryTask?.cancel()
        retryTask = nil
        logger.info("Banner loaded")
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        bannerView.isHidden = true
        logger.error("Banner load: \(error.localizedDescription, privacy: .public)")
        requested = false
        nextRetryDate = Date().addingTimeInterval(30)
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            self?.loadIfReady()
        }
    }
}
