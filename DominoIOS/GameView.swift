import SwiftUI

struct GameView: View {
    let model: AppModel
    @State private var overlay: GameOverlay?
    @State private var confirmsLeaving = false

    var body: some View {
        if let session = model.session {
            GeometryReader { proxy in
                let isWide = proxy.size.width > proxy.size.height
                VStack(spacing: 0) {
                    let adHeight = bannerHeight(isWide: isWide)

                    GameTable(
                        model: model,
                        session: session,
                        size: CGSize(
                            width: proxy.size.width,
                            height: proxy.size.height - adHeight
                        ),
                        showRules: { overlay = .rules },
                        showMenu: { overlay = .pause }
                    )
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height - adHeight,
                        alignment: .top
                    )

                    AdMobBannerView(width: proxy.size.width)
                        .frame(width: proxy.size.width, height: adHeight)
                        .background(.white)
                        .clipped()
                }
            }
            .onAppear {
                AppOrientation.request(.landscapeRight)
            }
            .onDisappear {
                AppOrientation.request(.portrait)
            }
            .overlay {
                if let overlay {
                    GameOverlayView(
                        item: overlay,
                        model: model,
                        close: { self.overlay = nil },
                        leave: {
                            self.overlay = nil
                            confirmsLeaving = true
                        }
                    )
                }
            }
            .confirmationDialog(
                "Leave the table?",
                isPresented: $confirmsLeaving,
                titleVisibility: .visible
            ) {
                Button("Leave game", role: .destructive, action: model.leaveGame)
                Button("Rester", role: .cancel) {}
            } message: {
                Text("Your progress is saved automatically.")
            }
        }
    }

    private func bannerHeight(isWide: Bool) -> CGFloat {
        isWide ? 50 : 60
    }
}

private struct GameTable: View {
    let model: AppModel
    let session: GameSession
    let size: CGSize
    let showRules: () -> Void
    let showMenu: () -> Void

    private var compact: Bool {
        size.width < 780 || size.height < 500
    }

    var body: some View {
        ZStack {
            tableBackground
            board
            opponents
            topBar
            playerArea

            if session.game.isFinished {
                resultOverlay
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var tableBackground: some View {
        Image("TableScene")
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .overlay(
                LinearGradient(
                    colors: [
                        .black.opacity(0.18),
                        .clear,
                        .black.opacity(0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var tableRim: some View {
        RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.18)
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.55, blue: 0.18),
                        Color(red: 0.25, green: 0.07, blue: 0.02),
                        Color(red: 0.9, green: 0.38, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: compact ? 7 : 11
            )
            .padding(.horizontal, compact ? 22 : 36)
            .padding(.vertical, compact ? 38 : 52)
            .shadow(color: .black.opacity(0.7), radius: 14)
            .allowsHitTesting(false)
    }

    private var topBar: some View {
        VStack {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    DominoTileView(
                        tile: DominoTile(first: 2, second: 5),
                        width: compact ? 17 : 21
                    )
                    .rotationEffect(.degrees(-15))

                    Text("Dominoes")
                        .font((compact ? Font.headline : Font.title2).bold())
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(.black.opacity(0.65), in: .capsule)
                .overlay(Capsule().stroke(.white.opacity(0.35)))

                Spacer()

                VStack(spacing: 2) {
                    Text(
                        "\(session.isBlockGame ? "BLOCK" : "DRAW")  ·  \(session.difficulty.title.uppercased())  ·  \(session.targetScore) POINTS"
                    )
                    .font(.caption.bold())
                    Text("Round \(session.round)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.black.opacity(0.36), in: .capsule)

                Spacer()

                HStack(spacing: 8) {
                    TableIconButton(icon: "questionmark", action: showRules)
                    TableIconButton(
                        icon: model.soundEnabled
                            ? "speaker.wave.2.fill"
                            : "speaker.slash.fill"
                    ) {
                        model.soundEnabled.toggle()
                    }
                    TableIconButton(icon: "gearshape.fill", action: showMenu)
                }
            }
            .padding(.horizontal, compact ? 12 : 22)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var opponents: some View {
        ZStack {
            if session.game.hands.indices.contains(1) {
                OpponentBadge(
                    name: "Lucas",
                    avatar: "AvatarLucas",
                    tileCount: session.game.hands[1].count,
                    isActive: session.game.turn == 1,
                    direction: .horizontal
                )
                .position(x: size.width / 2, y: compact ? 80 : 100)
            }

            if session.game.hands.indices.contains(2) {
                OpponentBadge(
                    name: "Emma",
                    avatar: "AvatarEmma",
                    tileCount: session.game.hands[2].count,
                    isActive: session.game.turn == 2,
                    direction: .vertical
                )
                .position(
                    x: compact ? 78 : 105,
                    y: size.height * 0.38
                )
            }

            if session.game.hands.indices.contains(3) {
                OpponentBadge(
                    name: "Noah",
                    avatar: "AvatarNoah",
                    tileCount: session.game.hands[3].count,
                    isActive: session.game.turn == 3,
                    direction: .vertical
                )
                .position(
                    x: size.width - (compact ? 78 : 105),
                    y: size.height * 0.38
                )
            }
        }
    }

    private var board: some View {
        let boardWidth = size.width * (compact ? 0.54 : 0.58)
        let boardHeight = size.height * 0.32

        return ZStack {
            BoardChain(tiles: session.game.board, compact: compact)
                .frame(width: boardWidth, height: boardHeight)

            if model.isSelectedTileLegal(on: .left) {
                BoardPlayTarget(title: "Play", side: .left) {
                    model.playSelected(on: .left)
                }
                .offset(x: -boardWidth / 2 - 36)
            }

            if model.isSelectedTileLegal(on: .right) {
                BoardPlayTarget(title: "Play", side: .right) {
                    model.playSelected(on: .right)
                }
                .offset(x: boardWidth / 2 + 36)
            }
        }
        .position(x: size.width / 2, y: size.height * 0.47)
    }

    private var playerArea: some View {
        HStack(alignment: .bottom, spacing: compact ? 8 : 16) {
            PlayerBadge(
                name: model.account.displayName,
                avatarIndex: model.selectedAvatarIndex,
                tileCount: session.game.hands[0].count,
                isActive: session.game.turn == 0
            )
            .frame(width: compact ? 120 : 165)

            VStack(spacing: 7) {
                Text(turnMessage)
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.48), in: .capsule)

                PlayerHand(
                    model: model,
                    tiles: session.game.hands[0],
                    isPlayersTurn: session.game.turn == 0,
                    compact: compact
                )
            }
            .frame(maxWidth: compact ? 460 : 620)

            TurnPanel(model: model, session: session, compact: compact)
                .frame(width: compact ? 132 : 175)
        }
        .padding(.horizontal, compact ? 12 : 24)
        .padding(.bottom, compact ? 8 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var turnMessage: String {
        if session.game.isFinished {
            return "Round complete"
        }
        return session.game.turn == 0
            ? "Your turn · choose a domino"
            : "\(playerName(session.game.turn)) is thinking…"
    }

    private func playerName(_ index: Int) -> String {
        switch index {
        case 1: "Lucas"
        case 2: "Emma"
        default: "Noah"
        }
    }

    private var resultOverlay: some View {
        RoundResult(model: model, session: session)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.28))
    }
}

private struct TableControlGlyph: View {
    let icon: String

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let ink = Color(red: 1, green: 0.97, blue: 0.89)
            let unit = min(size.width, size.height) / 24

            if icon == "questionmark" {
                context.draw(
                    Text("?").font(.system(size: 29 * unit, weight: .bold)).foregroundStyle(ink),
                    at: center
                )
            } else if icon.contains("speaker") {
                var speaker = Path()
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    CGPoint(x: center.x + x * unit, y: center.y + y * unit)
                }
                speaker.move(to: point(-11, -4))
                speaker.addLine(to: point(-6, -4))
                speaker.addLine(to: point(0, -10))
                speaker.addLine(to: point(0, 10))
                speaker.addLine(to: point(-6, 4))
                speaker.addLine(to: point(-11, 4))
                speaker.closeSubpath()
                context.stroke(speaker, with: .color(ink), style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round, lineJoin: .round))
                if icon.contains("slash") {
                    var slash = Path()
                    slash.move(to: point(5, -5))
                    slash.addLine(to: point(12, 5))
                    slash.move(to: point(12, -5))
                    slash.addLine(to: point(5, 5))
                    context.stroke(slash, with: .color(ink), style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round))
                } else {
                    for radius in [CGFloat(7), CGFloat(12)] {
                        var wave = Path()
                        wave.addArc(center: center, radius: radius * unit, startAngle: .degrees(-60), endAngle: .degrees(60), clockwise: false)
                        context.stroke(wave, with: .color(ink), style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round))
                    }
                }
            } else {
                context.stroke(Path(ellipseIn: CGRect(x: center.x - 8 * unit, y: center.y - 8 * unit, width: 16 * unit, height: 16 * unit)), with: .color(ink), lineWidth: 2.1 * unit)
                context.stroke(Path(ellipseIn: CGRect(x: center.x - 3 * unit, y: center.y - 3 * unit, width: 6 * unit, height: 6 * unit)), with: .color(ink), lineWidth: 2.1 * unit)
                for index in 0..<8 {
                    let angle = CGFloat(index) * .pi / 4
                    var tooth = Path()
                    tooth.move(to: CGPoint(x: center.x + sin(angle) * 8 * unit, y: center.y - cos(angle) * 8 * unit))
                    tooth.addLine(to: CGPoint(x: center.x + sin(angle) * 12 * unit, y: center.y - cos(angle) * 12 * unit))
                    context.stroke(tooth, with: .color(ink), style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round))
                }
            }
        }
    }
}

private struct TableIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TableControlGlyph(icon: icon)
                .frame(width: 22, height: 22)
                .frame(width: 46, height: 46)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.26, blue: 0.32),
                            Color(red: 0.04, green: 0.09, blue: 0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: .circle
                )
                .overlay(Circle().stroke(Color(red: 0.54, green: 0.57, blue: 0.63), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

private enum OpponentDirection {
    case horizontal
    case vertical
}

private struct OpponentBadge: View {
    let name: LocalizedStringKey
    let avatar: String
    let tileCount: Int
    let isActive: Bool
    let direction: OpponentDirection

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: -5) {
                Image(avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(.circle)
                    .overlay(
                        Circle().stroke(
                            isActive ? .yellow : .white.opacity(0.5),
                            lineWidth: isActive ? 3 : 1
                        )
                    )
                    .zIndex(1)

                VStack(spacing: 1) {
                    Text(name).font(.headline)
                    Text("\(tileCount)").font(.title3.bold()).monospacedDigit()
                }
                .frame(width: 90, height: 52)
                .background(
                    Color(red: 0.03, green: 0.1, blue: 0.2).opacity(0.95),
                    in: UnevenRoundedRectangle(
                        bottomTrailingRadius: 24,
                        topTrailingRadius: 24
                    )
                )
                .overlay(
                    UnevenRoundedRectangle(
                        bottomTrailingRadius: 24,
                        topTrailingRadius: 24
                    )
                    .stroke(isActive ? .yellow : .white.opacity(0.3))
                )
            }

            HiddenTiles(count: tileCount, direction: direction)
        }
        .shadow(
            color: isActive ? .yellow.opacity(0.5) : .black.opacity(0.55),
            radius: isActive ? 10 : 5
        )
    }
}

private struct HiddenTiles: View {
    let count: Int
    let direction: OpponentDirection

    var body: some View {
        Group {
            if direction == .horizontal {
                HStack(spacing: -3) {
                    tiles
                }
            } else {
                VStack(spacing: -19) {
                    tiles
                }
            }
        }
    }

    @ViewBuilder
    private var tiles: some View {
        ForEach(0..<min(count, 7), id: \.self) { _ in
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [.white, Color(white: 0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: direction == .horizontal ? 18 : 14,
                    height: direction == .horizontal ? 34 : 26
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
        }
    }
}

private struct PlayerBadge: View {
    let name: String
    let avatarIndex: Int
    let tileCount: Int
    let isActive: Bool

    var body: some View {
        HStack(spacing: -5) {
            AvatarCatalogView(index: avatarIndex, size: 64)
                .overlay(
                    Circle().stroke(
                        isActive ? .yellow : .white.opacity(0.5),
                        lineWidth: isActive ? 3 : 1
                    )
                )
                .zIndex(1)

            VStack(spacing: 1) {
                Text(name).font(.headline).lineLimit(1).minimumScaleFactor(0.72)
                Text("\(tileCount)").font(.title3.bold()).monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 55)
            .background(
                Color(red: 0.03, green: 0.1, blue: 0.2).opacity(0.96),
                in: UnevenRoundedRectangle(
                    bottomTrailingRadius: 25,
                    topTrailingRadius: 25
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    bottomTrailingRadius: 25,
                    topTrailingRadius: 25
                )
                .stroke(isActive ? .yellow : .white.opacity(0.3))
            )
        }
        .shadow(
            color: isActive ? .yellow.opacity(0.5) : .black.opacity(0.5),
            radius: 8
        )
    }
}

private struct PlayerHand: View {
    let model: AppModel
    let tiles: [DominoTile]
    let isPlayersTurn: Bool
    let compact: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: compact ? 5 : 8) {
                ForEach(tiles) { tile in
                    DominoTileView(
                        tile: tile,
                        isSelected: model.selectedTileID == tile.id,
                        width: compact ? 38 : 48
                    )
                    .offset(y: model.selectedTileID == tile.id ? -9 : 0)
                    .brightness(isPlayersTurn && model.isTilePlayable(tile) ? 0.10 : 0)
                    .opacity(isPlayersTurn && !model.isTilePlayable(tile) ? 0.42 : 1)
                    .onTapGesture {
                        model.select(tileID: tile.id)
                    }
                    .animation(.snappy, value: model.selectedTileID)
                    .disabled(!isPlayersTurn)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 11)
            .padding(.bottom, 3)
        }
        .scrollIndicators(.hidden)
        .frame(height: compact ? 88 : 108)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("Your hand")
    }
}

private struct TurnPanel: View {
    let model: AppModel
    let session: GameSession
    let compact: Bool

    private var canPlayLeft: Bool {
        model.isSelectedTileLegal(on: .left)
    }

    private var canPlayRight: Bool {
        model.isSelectedTileLegal(on: .right)
    }

    private var canDrawOrPass: Bool {
        session.game.turn == 0
            && !session.game.isFinished
            && !session.game.canCurrentPlayerPlay()
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.stack.fill")
                Text("Boneyard · \(session.game.stock.count)")
            }
            .font(.caption.bold())
            .foregroundStyle(.white.opacity(0.9))

            Button("Leave table", action: model.leaveGame)
                .buttonStyle(TableSecondaryButtonStyle())

            Button {
                if canPlayLeft && !canPlayRight {
                    model.playSelected(on: .left)
                } else if canPlayRight && !canPlayLeft {
                    model.playSelected(on: .right)
                } else if canDrawOrPass {
                    model.drawOrPass()
                }
            } label: {
                Label(
                    canDrawOrPass
                        ? (session.isBlockGame || session.game.stock.isEmpty ? "Pass" : "Draw")
                        : "Play",
                    systemImage: canDrawOrPass ? "rectangle.stack.fill" : "play.fill"
                )
            }
            .buttonStyle(TablePlayButtonStyle())
            .disabled(canPlayLeft == canPlayRight && !canDrawOrPass)
        }
        .font(compact ? .caption.bold() : .subheadline.bold())
    }
}

private struct TablePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 38)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.35, blue: 0.61),
                        Color(red: 0.04, green: 0.12, blue: 0.25)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: .capsule
            )
            .overlay(Capsule().stroke(.white.opacity(0.38)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct TablePlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.bold())
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.38, green: 0.86, blue: 0.08),
                        Color(red: 0.05, green: 0.48, blue: 0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: .capsule
            )
            .overlay(Capsule().stroke(Color(red: 0.72, green: 1, blue: 0.27), lineWidth: 2))
            .shadow(color: .black.opacity(0.45), radius: 5, y: 3)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct TableSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 34)
            .foregroundStyle(.white)
            .background(.black.opacity(0.52), in: .capsule)
            .overlay(Capsule().stroke(.white.opacity(0.3)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct BoardPlayTarget: View {
    let title: LocalizedStringKey
    let side: BoardSide
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(Color(red: 1, green: 0.9, blue: 0.55))
                .frame(width: 66, height: 66)
                .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.yellow.opacity(0.9), lineWidth: 2)
                )
                .shadow(color: .yellow.opacity(0.55), radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(side == .left ? "Play on the left" : "Play on the right")
    }
}

struct BoardChain: View {
    let tiles: [DominoTile]
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            if tiles.isEmpty {
                Text("The highest double starts")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.95, green: 0.82, blue: 0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let placements = ChainLayout.build(for: tiles)
                let bounds = chainBounds(placements)
                let unit = min(
                    compact ? 37 : 46,
                    max(13, (proxy.size.width - 20) / max(bounds.width, 1)),
                    max(13, (proxy.size.height - 18) / max(bounds.height, 1))
                )

                ZStack {
                    ForEach(placements) { placement in
                        DominoTileView(tile: placement.tile, width: unit)
                            .rotationEffect(placement.angle)
                            .position(
                                x: proxy.size.width / 2
                                    + (placement.center.x - bounds.midX) * unit,
                                y: proxy.size.height / 2
                                    + (placement.center.y - bounds.midY) * unit
                            )
                            .transition(.scale(scale: 0.75).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.32, bounce: 0.18), value: tiles.count)
            }
        }
    }

    private func chainBounds(_ placements: [ChainPlacement]) -> CGRect {
        placements.reduce(CGRect.null) { bounds, placement in
            bounds.union(
                CGRect(
                    x: placement.center.x - placement.cellWidth / 2,
                    y: placement.center.y - placement.cellHeight / 2,
                    width: placement.cellWidth,
                    height: placement.cellHeight
                )
            )
        }
    }
}

private struct AndroidTrophyGlyph: View {
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 24
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: center.x + x * unit, y: center.y + y * unit)
            }
            var cup = Path(roundedRect: CGRect(x: point(-7, -10).x, y: point(-7, -10).y, width: 14 * unit, height: 14 * unit), cornerRadius: 2 * unit)
            cup.move(to: point(0, 4))
            cup.addLine(to: point(0, 11))
            cup.move(to: point(-6, 12))
            cup.addLine(to: point(6, 12))
            cup.addArc(center: point(-7.5, -3), radius: 5.5 * unit, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
            cup.addArc(center: point(7.5, -3), radius: 5.5 * unit, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            context.stroke(cup, with: .foreground, style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct GameCapsuleButton: View {
    let title: String
    var goldStyle = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(goldStyle ? Color(red: 0.07, green: 0.13, blue: 0.22) : Color(red: 1, green: 0.97, blue: 0.89))
                .padding(.horizontal, 24)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: goldStyle
                            ? [Color(red: 1, green: 0.89, blue: 0.41), Color(red: 0.95, green: 0.64, blue: 0.03)]
                            : [Color(red: 0.2, green: 0.31, blue: 0.47), Color(red: 0.1, green: 0.18, blue: 0.31)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: Color.black.opacity(0.4), radius: 5, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct RoundResult: View {
    let model: AppModel
    let session: GameSession

    var body: some View {
        VStack(spacing: 14) {
            AndroidTrophyGlyph()
                .frame(width: 44, height: 44)
                .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.35))
            Text(resultText).font(.system(size: 28, weight: .bold))
            Text("+\(session.game.award) points")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.35))
            GameCapsuleButton(
                title: session.matchWinner == nil ? "Next round" : "New game",
                goldStyle: true
            ) {
                session.matchWinner == nil
                    ? model.nextRound()
                    : model.newMatch()
            }
        }
        .padding(30)
        .background(
            Color(red: 0.03, green: 0.08, blue: 0.15).opacity(0.96),
            in: RoundedRectangle(cornerRadius: 26)
        )
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.3)))
        .shadow(radius: 20)
        .frame(maxWidth: 360)
    }

    private var resultText: String {
        guard let winner = session.game.winner else { return "Drawn round" }
        return winner == 0 ? "You win!" : "Player \(winner + 1) wins"
    }
}

private enum GameOverlay: String, Identifiable {
    case pause
    case rules

    var id: String { rawValue }
}

private struct GameSettingButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
            Spacer()
            Text(enabled ? "Yes" : "No")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(enabled ? Color(red: 1, green: 0.82, blue: 0.35) : Color(red: 0.68, green: 0.76, blue: 0.86))
        }
        .foregroundStyle(Color(red: 1, green: 0.97, blue: 0.89))
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(Color(red: 0.1, green: 0.18, blue: 0.31), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.25)))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

private struct GameOverlayView: View {
    let item: GameOverlay
    @Bindable var model: AppModel
    let close: () -> Void
    let leave: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.09, blue: 0.16)
                .opacity(0.84)
                .ignoresSafeArea()
                .onTapGesture(perform: close)

            VStack(spacing: 16) {
                Text(item == .rules ? "How to play" : "Your game")
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.97, blue: 0.89))

                if item == .rules {
                    RulesSummary()
                    GameCapsuleButton(title: "Return to game", goldStyle: true, action: close)
                } else {
                    Text("Your progress is saved automatically.")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(red: 0.68, green: 0.76, blue: 0.86))
                    GameCapsuleButton(title: "Continue", goldStyle: true, action: close)
                    GameSettingButton(title: "Sound effects", enabled: model.soundEnabled) {
                        model.soundEnabled.toggle()
                    }
                    GameSettingButton(title: "Vibrations", enabled: model.hapticsEnabled) {
                        model.hapticsEnabled.toggle()
                    }
                    GameCapsuleButton(title: "Leave table", action: leave)
                }
            }
            .padding(26)
            .frame(width: item == .rules ? 560 : 460)
            .background(Color(red: 0.03, green: 0.1, blue: 0.2).opacity(0.97), in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.white.opacity(0.25)))
            .shadow(color: Color.black.opacity(0.75), radius: 24, y: 12)
        }
    }
}

private struct RulesSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Match a value to either open end.")
            Text("Doubles are placed crosswise and do not create a branch.")
            Text("In Draw mode, draw until you can play. In Block mode, pass.")
            Text("The first player with no dominoes wins the round.")
        }
        .font(.system(size: 16))
        .foregroundStyle(Color(red: 1, green: 0.97, blue: 0.89))
        .padding(20)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
    }
}
