import SwiftUI

struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.route == .game || model.route == .onlineGame {
                gameContent
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 0) {
                    menuContent
                    AdBannerSlot()
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .tint(Color(red: 0.96, green: 0.72, blue: 0.22))
        .onAppear {
            updateOrientation(for: model.route)
        }
        .onChange(of: model.route) { _, route in
            updateOrientation(for: route)
        }
    }

    @ViewBuilder
    private var gameContent: some View {
        if model.route == .onlineGame {
            OnlineGameView(model: model)
        } else {
            GameView(model: model)
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        ZStack {
            SceneBackground(isTable: false)

            switch model.route {
            case .home:
                HomeView(model: model)
            case .setup:
                SetupView(model: model)
            case .online:
                OnlineView(model: model)
            case .rules:
                RulesView(model: model)
            case .settings:
                SettingsView(model: model)
            case .profile:
                ProfileView(model: model)
            case .onlineGame, .game:
                EmptyView()
            }
        }
    }

    private func updateOrientation(for route: AppModel.Route) {
        AppOrientation.request(route == .game || route == .onlineGame ? .landscapeRight : .portrait)
    }
}

private struct AdBannerSlot: View {
    var body: some View {
        GeometryReader { proxy in
            AdMobBannerView(width: proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .frame(height: 63)
        .background(Color.white)
    }
}

private struct SceneBackground: View {
    let isTable: Bool

    var body: some View {
        Image(isTable ? "TableScene" : "MenuScene")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
            .overlay(Color(red: 0.01, green: 0.05, blue: 0.11).opacity(isTable ? 0.04 : 0.12))
    }
}
