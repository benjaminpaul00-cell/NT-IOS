import SwiftUI
import UIKit

private let ivory = Color(red: 1, green: 0.97, blue: 0.89)
private let mutedBlue = Color(red: 0.68, green: 0.76, blue: 0.86)
private let gold = Color(red: 1, green: 0.82, blue: 0.35)

struct HomeView: View {
    let model: AppModel

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 480, proxy.size.height / 850)

            HomeMenuCanvas(model: model)
                .frame(width: 480, height: 850)
                .scaleEffect(x: scale * 0.95, y: scale, anchor: .top)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .offset(y: -20)
        }
    }
}

private struct HomeMenuCanvas: View {
    let model: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            profileButton
                .frame(width: 185, height: 46)
                .position(x: 364.5, y: 40)

            Image("DominoLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 428, height: 270)
                .position(x: 240, y: 220)
                .accessibilityLabel("Dominoes")

            VStack(spacing: 15) {
                MenuButton(
                    title: model.session == nil ? "Play" : "Resume",
                    icon: "play.fill",
                    style: .gold
                ) {
                    model.session == nil
                        ? model.navigate(to: .setup)
                        : model.resumeGame()
                }
                .frame(height: 64)

                MenuButton(title: "Online multiplayer", icon: "person.3.fill") {
                    model.navigate(to: .online)
                }
                MenuButton(title: "How to play", icon: "book.closed.fill") {
                    model.navigate(to: .rules)
                }
                MenuButton(title: "Settings", icon: "gearshape.fill") {
                    model.navigate(to: .settings)
                }
            }
            .frame(width: 360)
            .position(x: 240, y: 535.5)
        }
    }

    private var profileButton: some View {
        Button {
            model.navigate(to: .profile)
        } label: {
            HStack(spacing: 9) {
                AvatarCatalogView(index: model.selectedAvatarIndex, size: 39)
                    .overlay(Circle().stroke(gold, lineWidth: 1.5))
                Text("My profile")
                    .font(.headline.bold())
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .foregroundStyle(ivory)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.17, green: 0.25, blue: 0.36),
                        Color(red: 0.03, green: 0.1, blue: 0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: .capsule
            )
            .overlay(Capsule().stroke(mutedBlue.opacity(0.55), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

struct SetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        PageScaffold(model: model, title: "Your next game", subtitle: "Choose your table and challenge.") {
            VStack(alignment: .leading, spacing: 22) {
                ChoiceSection(title: "PLAYERS") {
                    HStack(spacing: 10) {
                        ForEach(2...4, id: \.self) { count in
                            AndroidChoiceButton(title: "\(count) players", selected: model.playerCount == count) {
                                model.playerCount = count
                            }
                        }
                    }
                }
                ChoiceSection(title: "DIFFICULTY") {
                    HStack(spacing: 10) {
                        ForEach(Difficulty.allCases) { difficulty in
                            AndroidChoiceButton(title: difficulty.title, selected: model.difficulty == difficulty) {
                                model.difficulty = difficulty
                            }
                        }
                    }
                }
                ChoiceSection(title: "RULES") {
                    HStack(spacing: 13) {
                        AndroidChoiceButton(title: "Draw", selected: !model.isBlockGame) {
                            model.isBlockGame = false
                        }
                        AndroidChoiceButton(title: "Block", selected: model.isBlockGame) {
                            model.isBlockGame = true
                        }
                    }
                }
                ChoiceSection(title: "TARGET SCORE") {
                    HStack(spacing: 13) {
                        AndroidChoiceButton(title: "100 points", selected: model.targetScore == 100) {
                            model.targetScore = 100
                        }
                        AndroidChoiceButton(title: "150 points", selected: model.targetScore == 150) {
                            model.targetScore = 150
                        }
                    }
                }
            }
            .gameCard()

            Text("You + \(model.playerCount - 1) computer\(model.playerCount > 2 ? "s" : "")")
                .foregroundStyle(mutedBlue)
            MenuButton(title: "Start game", icon: "play.fill", style: .gold, action: model.startGame)
            Text("Your game is saved automatically.").font(.caption).foregroundStyle(mutedBlue)
        }
    }
}

struct RulesView: View {
    let model: AppModel
    private let sections = [
        ("01  One game, 28 possibilities", "The game has 28 dominoes, from double blank to double six. Two to four players compete individually."),
        ("02  Dealing", "Draw: 7 dominoes each. Block: 7 with two players, 5 with three or four. The highest double starts."),
        ("03  Your turn", "Match a domino to either open end. Doubles are placed crosswise."),
        ("04  No possible move?", "In Draw mode, draw until you can play. In Block mode, pass immediately."),
        ("05  End of round", "Play your last domino to win. If everyone passes, the lowest total wins."),
        ("06  Score", "The winner scores the points left in the opponents’ hands. Reach the target score to win.")
    ]

    var body: some View {
        PageScaffold(model: model, title: "How to play", subtitle: "Easy to learn. Fun to master.") {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(sections, id: \.0) { section in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(section.0).font(.headline).foregroundStyle(gold)
                        Text(section.1).foregroundStyle(ivory)
                    }
                }
            }.gameCard()
            MenuButton(title: "Play", style: .blue) { model.navigate(to: .setup) }
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        PageScaffold(model: model, title: "Settings", subtitle: "Play your way.") {
            VStack(spacing: 18) {
                SettingRow(title: "Sound effects", subtitle: "Dominoes and results", isOn: $model.soundEnabled)
                Divider().overlay(.white.opacity(0.2))
                SettingRow(title: "Vibrations", subtitle: "Light touch feedback", isOn: $model.hapticsEnabled)
            }.gameCard()
            MenuButton(title: "My profile", icon: "person.2.fill") { model.navigate(to: .profile) }
            MenuButton(title: "Ad privacy", icon: "hand.raised.fill") {
                AdMobService.shared.presentPrivacyOptions()
            }
            Text("Dominoes · version iOS").font(.caption).foregroundStyle(mutedBlue)
        }
    }
}

struct OnlineView: View {
    let model: AppModel
    @State private var selectedPlayers = 4
    @State private var roomCode = ""
    @State private var friendCodeInput = ""
    @State private var showsJoinPrompt = false
    @State private var showsFriends = false

    private var online: OnlineGameService {
        model.online
    }

    private var account: AccountService {
        model.account
    }

    var body: some View {
        PageScaffold(model: model, title: "Play online", subtitle: "Friends and new opponents at the same table.") {
            MenuButton(title: "My profile", icon: "person.crop.circle", style: .light) {
                model.navigate(to: .profile)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("PLAYERS AT THE TABLE").font(.caption.bold()).foregroundStyle(gold)
                HStack(spacing: 10) {
                    ForEach(2...4, id: \.self) { count in
                        AndroidChoiceButton(title: "\(count)", selected: selectedPlayers == count) {
                            selectedPlayers = count
                        }
                    }
                }
            }
            .gameCard()

            if let room = online.room, !room.isPlaying {
                VStack(spacing: 14) {
                    Text(room.isPrivate ? "PRIVATE TABLE" : "QUICK MATCH")
                        .font(.title2.bold())
                    Text("Table code")
                        .foregroundStyle(mutedBlue)
                    Text(room.code)
                        .font(.system(.largeTitle, design: .monospaced).bold())
                        .foregroundStyle(gold)

                    HStack(spacing: 12) {
                        AndroidCompactButton(title: "Copy", goldStyle: true) {
                            UIPasteboard.general.string = room.code
                        }
                        ShareLink(item: "Join my Dominoes table with code \(room.code)") {
                            Text("Share")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.22))
                                .padding(.horizontal, 18)
                                .frame(height: 42)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 1, green: 0.89, blue: 0.41), Color(red: 0.95, green: 0.64, blue: 0.03)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1.2))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(room.playerIDs.enumerated()), id: \.element) { index, _ in
                            Text(
                                "\(index + 1). \(room.playerNames.indices.contains(index) ? room.playerNames[index] : "Player \(index + 1)")"
                            )
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(room.playerIDs.count) / \(room.maxPlayers) players")
                        .foregroundStyle(mutedBlue)

                    if room.isPrivate && room.hostID == online.playerID {
                        MenuButton(
                            title: "Start game",
                            icon: "play.fill",
                            style: .gold
                        ) {
                            Task { await online.startRoom() }
                        }
                        .disabled(room.playerIDs.count < 2)
                    } else {
                        Text("Waiting for players…")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(gold)
                    }

                    MenuButton(title: "Leave table") {
                        online.leaveRoom()
                    }
                }
                .foregroundStyle(ivory)
                .gameCard()
            } else {
                MenuButton(title: "Create a private table", icon: "person.3.fill", style: .gold) {
                    Task {
                        await online.createPrivateRoom(
                            players: selectedPlayers,
                            avatarIndex: model.selectedAvatarIndex
                        )
                    }
                }

                MenuButton(title: "Join with a code", icon: "person.3.fill") {
                    showsJoinPrompt = true
                }

                MenuButton(title: "Quick match", icon: "play.fill") {
                    Task {
                        await online.findQuickMatch(
                            players: selectedPlayers,
                            avatarIndex: model.selectedAvatarIndex
                        )
                    }
                }
            }

            if !account.invitations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("INVITATIONS").font(.caption.bold()).foregroundStyle(gold)
                    ForEach(account.invitations) { invitation in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(invitation.senderName).font(.headline)
                                Text("Table \(invitation.roomCode)").font(.caption)
                            }
                            Spacer()
                            AndroidCompactButton(title: "Join", goldStyle: true) {
                                Task {
                                    await online.joinRoom(
                                        code: invitation.roomCode,
                                        avatarIndex: model.selectedAvatarIndex
                                    )
                                    await account.dismissInvitation(invitation)
                                }
                            }
                        }
                    }
                }
                .gameCard()
            }

            MenuButton(title: "Friends and invitations", icon: "person.3.fill") {
                showsFriends.toggle()
            }

            if showsFriends {
                VStack(alignment: .leading, spacing: 12) {
                    Text("FRIENDS").font(.caption.bold()).foregroundStyle(gold)
                HStack {
                    TextField("Exact username", text: $friendCodeInput)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: friendCodeInput) { _, value in
                            friendCodeInput = String(
                                value.uppercased()
                                    .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                    .prefix(20)
                            )
                        }
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ivory)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18)))
                    AndroidCompactButton(title: "Add", goldStyle: true) {
                        Task {
                            await account.addFriend(code: friendCodeInput)
                            friendCodeInput = ""
                        }
                    }
                }

                if account.friends.isEmpty {
                    Text("Find Android and iOS players by their exact username. Table codes contain 8 characters.")
                        .font(.footnote)
                        .foregroundStyle(mutedBlue)
                } else {
                    ForEach(account.friends) { friend in
                        HStack {
                            AvatarCatalogView(index: friend.avatarIndex, size: 38)
                            Text(friend.displayName)
                            Spacer()
                            if let room = online.room, !room.isPlaying {
                                AndroidCompactButton(title: "Invite") {
                                    Task {
                                        await account.invite(friend: friend, to: room.code)
                                    }
                                }
                            }
                        }
                    }
                }
            }
                .foregroundStyle(ivory)
                .gameCard()
            }

            if online.isWorking {
                Text("Connecting…")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(gold)
            }

            Text("The game starts automatically when the table is full.")
                .font(.footnote)
                .foregroundStyle(mutedBlue)
                .multilineTextAlignment(.center)
        }
        .overlay {
            if showsJoinPrompt {
                AndroidPromptOverlay(
                    title: "Multiplayer",
                    message: "Enter an 8-character table code.",
                    placeholder: "8-character code",
                    text: $roomCode,
                    cancel: { showsJoinPrompt = false },
                    confirm: {
                        showsJoinPrompt = false
                        Task {
                            await online.joinRoom(
                                code: roomCode,
                                avatarIndex: model.selectedAvatarIndex
                            )
                        }
                    }
                )
            }
        }
        .onChange(of: online.room?.isPlaying) { _, isPlaying in
            if isPlaying == true {
                model.navigate(to: .onlineGame)
            }
        }
        .task {
            if await online.signInIfNeeded() {
                await account.refresh(avatarIndex: model.selectedAvatarIndex)
            }
        }
        .alert("Multiplayer", isPresented: errorBinding) {
            Button("OK", action: online.clearError)
        } message: {
            Text(online.errorMessage ?? "")
        }
        .alert("Profile", isPresented: accountErrorBinding) {
            Button("OK", action: account.clearError)
        } message: {
            Text(account.errorMessage ?? "")
        }
    }

    private var accountErrorBinding: Binding<Bool> {
        Binding(
            get: { account.errorMessage != nil },
            set: { if !$0 { account.clearError() } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { online.errorMessage != nil },
            set: { if !$0 { online.clearError() } }
        )
    }
}

struct ProfileView: View {
    let model: AppModel
    @State private var showsAvatarPicker = false
    @State private var profileName = ""

    private var account: AccountService {
        model.account
    }

    var body: some View {
        PageScaffold(model: model, title: "My profile", subtitle: "Your identity at every table.") {
            AvatarCatalogView(index: model.selectedAvatarIndex, size: 130)
                .overlay(Circle().stroke(gold, lineWidth: 3))
            MenuButton(title: "Choose an avatar") { showsAvatarPicker = true }

            VStack(spacing: 12) {
                TextField("Your name", text: $profileName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ivory)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18)))
                MenuButton(title: "Save profile", style: .gold) {
                    Task {
                        await account.updateProfile(
                            name: profileName,
                            avatarIndex: model.selectedAvatarIndex
                        )
                    }
                }

                if !account.displayName.isEmpty {
                    Text("USERNAME").font(.caption.bold()).foregroundStyle(gold)
                    Text(account.displayName)
                        .font(.system(.title2, design: .monospaced).bold())
                    MenuButton(title: "Copy my username") {
                        UIPasteboard.general.string = account.displayName
                    }
                }
            }
            .foregroundStyle(ivory)
            .gameCard()

            if account.isAuthenticatedProfile {
                Label("Secure account connected", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .gameCard()
            } else {
                Text("Secure your profile with Apple or Google to access it on your other devices.")
                    .foregroundStyle(ivory)
                    .multilineTextAlignment(.center)
                    .gameCard()
                AccountAuthenticationView(model: model)
            }
        }
        .task {
            if await model.online.signInIfNeeded() {
                await account.refresh(avatarIndex: model.selectedAvatarIndex)
                profileName = account.displayName
            }
        }
        .fullScreenCover(isPresented: $showsAvatarPicker) {
            AvatarPickerView(model: model)
        }
        .alert("Profile", isPresented: errorBinding) {
            Button("OK", action: account.clearError)
        } message: {
            Text(account.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { account.errorMessage != nil },
            set: { if !$0 { account.clearError() } }
        )
    }
}

private struct PageScaffold<Content: View>: View {
    let model: AppModel
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Image("DominoLogo").resizable().scaledToFit().frame(height: 90)
                    Button { model.navigate(to: .home) } label: {
                        AndroidGlyph(kind: .back)
                            .frame(width: 22, height: 22)
                            .frame(width: 46, height: 46)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.22, green: 0.26, blue: 0.32), Color(red: 0.04, green: 0.09, blue: 0.16)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                in: Circle()
                            )
                            .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.5))
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                }
                VStack(spacing: 5) { Text(title).font(.title.bold()).foregroundStyle(ivory); Text(subtitle).font(.subheadline).foregroundStyle(mutedBlue) }
                content
            }
            .frame(maxWidth: 428)
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct AndroidCompactButton: View {
    let title: String
    var goldStyle = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(goldStyle ? Color(red: 0.07, green: 0.13, blue: 0.22) : ivory)
                .padding(.horizontal, 18)
                .frame(height: 42)
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
                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }
}

private struct AndroidPromptOverlay: View {
    let title: String
    let message: String
    let placeholder: String
    @Binding var text: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)

            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(ivory)
                Text(message)
                    .font(.system(size: 17))
                    .foregroundStyle(mutedBlue)
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ivory)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18)))
                HStack(spacing: 12) {
                    MenuButton(title: "Cancel", action: cancel)
                    MenuButton(title: "OK", style: .gold, action: confirm)
                }
            }
            .padding(26)
            .frame(width: 360)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.18, green: 0.21, blue: 0.25), Color(red: 0.08, green: 0.1, blue: 0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 28)
            )
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.22), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.8), radius: 24, y: 12)
        }
    }
}

private struct AndroidChoiceButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(selected ? ivory : mutedBlue)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    LinearGradient(
                        colors: selected
                            ? [Color(red: 0.84, green: 0.67, blue: 0.27), Color(red: 0.55, green: 0.39, blue: 0.11)]
                            : [Color(red: 0.15, green: 0.24, blue: 0.36), Color(red: 0.08, green: 0.16, blue: 0.26)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(selected ? gold : Color(red: 0.29, green: 0.39, blue: 0.52), lineWidth: selected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ChoiceSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption.bold()).foregroundStyle(gold); content } }
}

private struct SettingRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 21, weight: .bold))
                Text(subtitle).font(.system(size: 14)).foregroundStyle(mutedBlue)
            }
            Spacer(minLength: 8)
            AndroidChoiceButton(title: isOn ? "Yes" : "No", selected: isOn) {
                isOn.toggle()
            }
            .frame(width: 110)
        }
        .foregroundStyle(ivory)
    }
}

private struct AndroidGlyph: View {
    enum Kind {
        case play
        case people
        case book
        case settings
        case back
        case none

        init(systemName: String) {
            switch systemName {
            case "play.fill": self = .play
            case "person.3.fill", "person.2.fill", "person.crop.circle": self = .people
            case "book.closed.fill": self = .book
            case "gearshape.fill": self = .settings
            default: self = .none
            }
        }
    }

    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 24
            var path = Path()

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: size.width / 2 + x * unit, y: size.height / 2 + y * unit)
            }

            switch kind {
            case .play:
                path.move(to: point(-7, -11))
                path.addLine(to: point(10, 0))
                path.addLine(to: point(-7, 11))
                path.closeSubpath()
                context.fill(path, with: .foreground)
            case .back:
                path.move(to: point(5, -9))
                path.addLine(to: point(-5, 0))
                path.addLine(to: point(5, 9))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round, lineJoin: .round))
            case .people:
                for (x, y, radius) in [(CGFloat(0), CGFloat(-7), CGFloat(4)), (-9, -4, 3), (9, -4, 3)] {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: point(x, y).x - radius * unit, y: point(x, y).y - radius * unit, width: radius * unit * 2, height: radius * unit * 2)),
                        with: .foreground,
                        lineWidth: 2.1 * unit
                    )
                }
                var bodies = Path()
                bodies.addArc(center: point(0, 7), radius: 7 * unit, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                bodies.addArc(center: point(-9, 7), radius: 5.5 * unit, startAngle: .degrees(180), endAngle: .degrees(330), clockwise: false)
                bodies.addArc(center: point(9, 7), radius: 5.5 * unit, startAngle: .degrees(210), endAngle: .degrees(360), clockwise: false)
                context.stroke(bodies, with: .foreground, style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round))
            case .book:
                path.move(to: point(0, -8))
                path.addCurve(to: point(-13, -9), control1: point(-4, -12), control2: point(-9, -12))
                path.addLine(to: point(-13, 11))
                path.addCurve(to: point(0, 12), control1: point(-8, 8), control2: point(-4, 8))
                path.addCurve(to: point(13, 11), control1: point(4, 8), control2: point(8, 8))
                path.addLine(to: point(13, -9))
                path.addCurve(to: point(0, -8), control1: point(9, -12), control2: point(4, -12))
                path.addLine(to: point(0, 12))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round, lineJoin: .round))
            case .settings:
                context.stroke(Path(ellipseIn: CGRect(x: point(0, 0).x - 8 * unit, y: point(0, 0).y - 8 * unit, width: 16 * unit, height: 16 * unit)), with: .foreground, lineWidth: 2.1 * unit)
                context.stroke(Path(ellipseIn: CGRect(x: point(0, 0).x - 3 * unit, y: point(0, 0).y - 3 * unit, width: 6 * unit, height: 6 * unit)), with: .foreground, lineWidth: 2.1 * unit)
                for angle in stride(from: 0.0, to: 360.0, by: 45.0) {
                    let radians = angle * .pi / 180
                    var tooth = Path()
                    tooth.move(to: point(CGFloat(sin(radians) * 8), CGFloat(-cos(radians) * 8)))
                    tooth.addLine(to: point(CGFloat(sin(radians) * 12), CGFloat(-cos(radians) * 12)))
                    context.stroke(tooth, with: .foreground, style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round))
                }
            case .none:
                break
            }
        }
    }
}

private enum MenuButtonStyle { case blue, gold, light }

private struct MenuButton: View {
    let title: LocalizedStringKey
    var icon: String?
    var style: MenuButtonStyle = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                    if let icon {
                        AndroidGlyph(kind: AndroidGlyph.Kind(systemName: icon))
                            .frame(width: 25, height: 25)
                    }
                    Text(title).font(.system(size: 19, weight: .bold))
                    if icon != nil { Spacer() }
                }
                .foregroundStyle(style == .gold || style == .light ? Color(red: 0.07, green: 0.13, blue: 0.22) : ivory)
                .frame(maxWidth: .infinity, minHeight: 58).padding(.horizontal, 24)
                .frame(maxWidth: 360)
                .background(buttonGradient, in: .capsule)
                .overlay(Capsule().stroke(.white.opacity(0.32), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 5)
        }.buttonStyle(.plain)
    }

    private var buttonGradient: LinearGradient {
        let colors: [Color] = switch style {
        case .blue: [Color(red: 0.2, green: 0.31, blue: 0.48), Color(red: 0.08, green: 0.16, blue: 0.28)]
        case .gold: [Color(red: 1, green: 0.89, blue: 0.4), Color(red: 0.95, green: 0.57, blue: 0.03)]
        case .light: [.white, Color(red: 0.86, green: 0.89, blue: 0.94)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

private extension View {
    func gameCard() -> some View { padding(20).background(Color(red: 0.03, green: 0.1, blue: 0.19).opacity(0.88), in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.18))) }
    func choiceChip(selected: Bool) -> some View { padding(.vertical, 12).background(selected ? gold.opacity(0.72) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(selected ? ivory : mutedBlue) }
}
