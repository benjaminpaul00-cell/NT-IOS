import SwiftUI

struct FeaturePlaceholderView: View {
    let route: AppRoute

    var body: some View {
        ZStack {
            NecroTheme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: icon).font(.system(size: 42, weight: .thin)).foregroundStyle(NecroTheme.accent)
                Text(title).font(.title2.weight(.black)).foregroundStyle(.white)
                Text("The native iOS service for this feature has not been implemented yet.")
                    .foregroundStyle(NecroTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: LocalizedStringKey {
        switch route {
        case .spiritBox: "SPIRIT BOX"
        case .evpRecorder: "EVP RECORDER"
        case .history: "SESSION HISTORY"
        case .settings: "SETTINGS"
        case .lexicon: "CUSTOM LEXICON"
        }
    }

    private var icon: String {
        switch route {
        case .spiritBox: "dot.radiowaves.left.and.right"
        case .evpRecorder: "waveform"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        case .lexicon: "text.book.closed"
        }
    }
}
