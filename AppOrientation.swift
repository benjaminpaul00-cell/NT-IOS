import UIKit

@MainActor
enum AppOrientation {
    static func request(_ orientations: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = orientations

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            return
        }

        let rootViewController = scene.windows
            .first(where: \.isKeyWindow)?
            .rootViewController

        requestSupportedOrientationsUpdate(from: rootViewController)

        // UIKit evaluates the view-controller masks before applying scene geometry.
        // Defer one run-loop turn so the new application mask is visible to that pass.
        DispatchQueue.main.async {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                print("Orientation request denied: \(error.localizedDescription)")
            }
        }
    }

    private static func requestSupportedOrientationsUpdate(from viewController: UIViewController?) {
        guard let viewController else {
            return
        }

        viewController.setNeedsUpdateOfSupportedInterfaceOrientations()

        for child in viewController.children {
            requestSupportedOrientationsUpdate(from: child)
        }

        if let presentedViewController = viewController.presentedViewController {
            requestSupportedOrientationsUpdate(from: presentedViewController)
        }
    }
}
