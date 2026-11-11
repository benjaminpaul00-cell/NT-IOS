import FirebaseAuth
import FirebaseFirestore
import Observation
import SwiftUI

struct OnlineRoom: Equatable {
    let code: String
    let hostID: String
    let playerIDs: [String]
    let avatarIndices: [Int]
    let playerNames: [String]
    let maxPlayers: Int
    let isPrivate: Bool
    let status: String
    let revision: Int
    let session: GameSession?

    var isPlaying: Bool {
        status == "playing" && session != nil
    }
}

private struct OnlineTableCanvas: View {
    let room: OnlineRoom
    let session: GameSession
    let playerIndex: Int
    @Binding var selectedTileID: DominoTile.ID?
    let leave: () -> Void
    let play: (BoardSide) -> Void
    let drawOrPass: () -> Void
    let nextRound: () -> Void

    private let ivory = Color(red: 1, green: 0.97, blue: 0.89)
    private let gold = Color(red: 1, green: 0.82, blue: 0.35)

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 560
            ZStack {
                Image("TableScene")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                VStack(spacing: 2) {
                    Text("\(session.isBlockGame ? "BLOCK" : "DRAW")  ·  ONLINE  ·  \(session.targetScore) POINTS")
                        .font(.system(size: compact ? 11 : 12, weight: .bold))
                    Text("Round \(session.round)")
                        .font(.system(size: compact ? 11 : 13))
                        .foregroundStyle(Color(red: 0.92, green: 0.68, blue: 0.32))
                }
                .foregroundStyle(ivory)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 10)

                opponentBadges(size: proxy.size, compact: compact)

                BoardChain(tiles: session.game.board, compact: compact)
                    .frame(width: proxy.size.width * 0.55, height: proxy.size.height * 0.34)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.48)

                playerArea(size: proxy.size, compact: compact)
            }
        }
    }

    @ViewBuilder
    private func opponentBadges(size: CGSize, compact: Bool) -> some View {
        ForEach(Array(session.game.hands.indices.filter { $0 != playerIndex }.enumerated()), id: \.element) { order, index in
            OnlinePlayerBadge(
                avatarIndex: room.avatarIndices.indices.contains(index) ? room.avatarIndices[index] : index,
                name: room.playerNames.indices.contains(index)
                    ? room.playerNames[index]
                    : "Player \(index + 1)",
                count: session.game.hands[index].count,
                active: session.game.turn == index
            )
            .position(opponentPosition(order: order, size: size, compact: compact))
        }
    }

    private func opponentPosition(order: Int, size: CGSize, compact: Bool) -> CGPoint {
        switch order {
        case 0:
            CGPoint(x: size.width / 2, y: compact ? 84 : 102)
        case 1:
            CGPoint(x: compact ? 92 : 118, y: size.height * 0.39)
        default:
            CGPoint(x: size.width - (compact ? 92 : 118), y: size.height * 0.39)
        }
    }

    private func playerArea(size: CGSize, compact: Bool) -> some View {
        let hand = session.game.hands[playerIndex]
        let isTurn = session.game.turn == playerIndex
        return VStack(spacing: 7) {
            Text(statusText)
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(ivory)
                .padding(.horizontal, 28)
                .frame(height: 31)
                .background(Color.black.opacity(0.48), in: Capsule())

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(hand) { tile in
                    let playable = session.game.isLegal(tile, on: .left) || session.game.isLegal(tile, on: .right)
                    DominoTileView(
                        tile: tile,
                        isSelected: selectedTileID == tile.id,
                        width: compact ? 39 : 50
                    )
                    .offset(y: selectedTileID == tile.id ? -10 : 0)
                    .brightness(isTurn && playable ? 0.10 : 0)
                    .opacity(isTurn && !playable ? 0.42 : 1)
                    .onTapGesture {
                        guard isTurn, playable else { return }
                        selectedTileID = selectedTileID == tile.id ? nil : tile.id
                    }
                }
            }

            HStack(spacing: 10) {
                if session.game.isFinished {
                    OnlineTableButton(title: session.matchWinner == nil ? "Next round" : "New game", goldStyle: true, action: nextRound)
                } else {
                    OnlineTableButton(title: "Left", enabled: canPlay(.left)) { play(.left) }
                    if !session.game.canCurrentPlayerPlay() {
                        OnlineTableButton(title: session.isBlockGame || session.game.stock.isEmpty ? "Pass" : "Draw", goldStyle: true, enabled: isTurn, action: drawOrPass)
                    }
                    OnlineTableButton(title: "Right", enabled: canPlay(.right)) { play(.right) }
                }
                OnlineTableButton(title: "Leave", action: leave)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    private var statusText: String {
        if session.game.isFinished { return "Round complete" }
        return session.game.turn == playerIndex
            ? "Your turn · choose a domino"
            : "Player \(session.game.turn + 1) is playing…"
    }

    private func canPlay(_ side: BoardSide) -> Bool {
        guard session.game.turn == playerIndex,
              let selectedTileID,
              let tile = session.game.hands[playerIndex].first(where: { $0.id == selectedTileID }) else {
            return false
        }
        return session.game.isLegal(tile, on: side)
    }
}

private struct OnlinePlayerBadge: View {
    let avatarIndex: Int
    let name: String
    let count: Int
    let active: Bool

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: -5) {
                AvatarCatalogView(index: avatarIndex, size: 62)
                    .overlay(Circle().stroke(active ? Color(red: 1, green: 0.82, blue: 0.35) : Color.white.opacity(0.5), lineWidth: active ? 3 : 1))
                    .zIndex(1)
                VStack(spacing: 1) {
                    Text(name).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text("\(count)").font(.system(size: 22, weight: .bold))
                }
                .foregroundStyle(Color(red: 1, green: 0.97, blue: 0.89))
                .frame(width: 105, height: 54)
                .background(Color(red: 0.03, green: 0.1, blue: 0.2).opacity(0.96), in: Capsule())
                .overlay(Capsule().stroke(active ? Color(red: 1, green: 0.82, blue: 0.35) : Color.white.opacity(0.3)))
            }
            HStack(spacing: -3) {
                ForEach(0..<min(count, 7), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [.white, Color(white: 0.62)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 18, height: 34)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.85)))
                }
            }
        }
        .shadow(color: active ? Color.yellow.opacity(0.45) : Color.black.opacity(0.55), radius: active ? 10 : 5)
    }
}

private struct OnlineTableButton: View {
    let title: String
    var goldStyle = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(goldStyle ? Color(red: 0.07, green: 0.13, blue: 0.22) : Color(red: 1, green: 0.97, blue: 0.89))
                .padding(.horizontal, 18)
                .frame(height: 40)
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
                .overlay(Capsule().stroke(Color.white.opacity(0.36), lineWidth: 1.2))
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

@MainActor
@Observable
final class OnlineGameService {
    private(set) var room: OnlineRoom?
    private(set) var playerID: String?
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    private let database = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var actionListener: ListenerRegistration?
    private var authoritativeSession: GameSession?

    var playerIndex: Int? {
        guard let playerID else { return nil }
        return room?.playerIDs.firstIndex(of: playerID)
    }

    var isSignedIn: Bool {
        Auth.auth().currentUser != nil
    }

    func signInIfNeeded() async -> Bool {
        if let user = Auth.auth().currentUser, !user.isAnonymous {
            playerID = user.uid
            do {
                let profile = try await database.collection("profiles").document(user.uid).getDocument()
                if profile.exists { return true }
                errorMessage = "Save your username in My Profile before playing online."
                return false
            } catch {
                errorMessage = firebaseMessage(error)
                return false
            }
        }
        errorMessage = "Sign in with Apple or Google before playing online."
        return false
    }

    func createPrivateRoom(players: Int, avatarIndex: Int) async {
        await createRoom(players: players, avatarIndex: avatarIndex, isPrivate: true)
    }

    func joinRoom(code: String, avatarIndex: Int) async {
        guard await beginOperation() else { return }
        defer { isWorking = false }

        let normalizedCode = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard normalizedCode.count == 8, let playerID else {
            errorMessage = "Enter an 8-character table code."
            return
        }

        do {
            try await join(document: database.collection("rooms").document(normalizedCode), playerID: playerID, avatarIndex: avatarIndex)
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    func findQuickMatch(players: Int, avatarIndex: Int) async {
        guard await beginOperation() else { return }
        defer { isWorking = false }
        guard let playerID else { return }

        do {
            let snapshot = try await database.collection("rooms")
                .whereField("status", isEqualTo: "waiting")
                .limit(to: 20)
                .getDocuments()

            if let document = snapshot.documents.first(where: {
                ($0.data()["discoverable"] as? Bool) == true
                    && ($0.data()["capacity"] as? Int) == players
            }) {
                try await join(document: document.reference, playerID: playerID, avatarIndex: avatarIndex)
            } else {
                try await createRoomDocument(
                    players: players,
                    avatarIndex: avatarIndex,
                    isPrivate: false,
                    playerID: playerID
                )
            }
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    func play(tileID: DominoTile.ID, side: BoardSide) async {
        guard let room, let playerIndex, room.session?.game.turn == playerIndex else { return }
        if room.hostID == playerID, var session = authoritativeSession,
           session.play(tileID: tileID, on: side) {
            authoritativeSession = session
            await publish(session, revision: room.revision + 1)
        } else {
            await submitAction(type: "play", tileID: tileID, left: side == .left)
        }
    }

    func drawOrPass() async {
        guard let room, let playerIndex, room.session?.game.turn == playerIndex else { return }
        if room.hostID == playerID, var session = authoritativeSession,
           session.drawOrPass() {
            authoritativeSession = session
            await publish(session, revision: room.revision + 1)
        } else {
            await submitAction(type: "draw", tileID: -1, left: false)
        }
    }

    func startNextRound() async {
        guard let room, let session = room.session,
              session.game.isFinished, session.matchWinner == nil else {
            return
        }
        if room.hostID == playerID, var authoritative = authoritativeSession {
            authoritative.startNextRound()
            authoritativeSession = authoritative
            await publish(authoritative, revision: room.revision + 1)
        } else {
            await submitAction(type: "next", tileID: -1, left: false)
        }
    }

    func startRoom() async {
        guard let room,
              let playerID,
              room.hostID == playerID,
              room.status == "waiting",
              room.playerIDs.count >= 2 else {
            return
        }

        let session = GameSession(
            players: room.playerIDs.count,
            difficulty: .medium,
            targetScore: 100,
            isBlockGame: false
        )
        authoritativeSession = session
        await publish(session, revision: room.revision + 1, starting: true)
        observeActions(roomCode: room.code)
    }

    func startNewMatch() async {
        guard let room, room.session?.matchWinner != nil else { return }
        if room.hostID == playerID {
            let session = GameSession(players: room.playerIDs.count, difficulty: .medium, targetScore: 100, isBlockGame: false)
            authoritativeSession = session
            AdMobService.shared.recordCompletedGame()
            await publish(session, revision: room.revision + 1)
        } else {
            await submitAction(type: "rematch", tileID: -1, left: false)
        }
    }

    func leaveRoom() {
        let departingRoom = room
        let departingPlayerID = playerID
        listener?.remove()
        actionListener?.remove()
        listener = nil
        actionListener = nil
        authoritativeSession = nil
        room = nil
        errorMessage = nil

        guard let departingRoom, let departingPlayerID else { return }
        Task {
            await removePlayer(
                departingPlayerID,
                fromRoomCode: departingRoom.code
            )
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func createRoom(players: Int, avatarIndex: Int, isPrivate: Bool) async {
        guard await beginOperation() else { return }
        defer { isWorking = false }
        guard let playerID else { return }

        do {
            try await createRoomDocument(
                players: players,
                avatarIndex: avatarIndex,
                isPrivate: isPrivate,
                playerID: playerID
            )
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    private func beginOperation() async -> Bool {
        errorMessage = nil
        isWorking = true
        guard await signInIfNeeded() else {
            isWorking = false
            return false
        }
        return true
    }

    private func createRoomDocument(
        players: Int,
        avatarIndex: Int,
        isPrivate: Bool,
        playerID: String
    ) async throws {
        let code = Self.makeCode()
        let profile = try await playerProfile(playerID)
        let playerName = profile.name
        let reference = database.collection("rooms").document(code)
        try await reference.setData([
            "protocol": 1,
            "host": playerID,
            "members": [playerID],
            "avatars": [playerID: profile.avatarID],
            "names": [playerID: playerName],
            "capacity": min(4, max(2, players)),
            "discoverable": !isPrivate,
            "random": !isPrivate,
            "status": "waiting",
            "revision": 0,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(3 * 60 * 60))
        ])
        observe(reference)
    }

    private func join(
        document: DocumentReference,
        playerID: String,
        avatarIndex: Int
    ) async throws {
        let profile = try await playerProfile(playerID)
        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(document)
                guard snapshot.exists, let data = snapshot.data() else {
                    throw OnlineGameError.message("This table could not be found.")
                }

                var playerIDs = data["members"] as? [String] ?? []
                var avatars = data["avatars"] as? [String: String] ?? [:]
                var names = data["names"] as? [String: String] ?? [:]
                let maxPlayers = data["capacity"] as? Int ?? 2
                let status = data["status"] as? String ?? "waiting"

                guard status == "waiting" else {
                    throw OnlineGameError.message("This game has already started.")
                }
                guard playerIDs.count < maxPlayers || playerIDs.contains(playerID) else {
                    throw OnlineGameError.message("This table is full.")
                }

                if !playerIDs.contains(playerID) {
                    playerIDs.append(playerID)
                    avatars[playerID] = profile.avatarID
                    names[playerID] = profile.name
                }

                transaction.updateData([
                    "members": playerIDs,
                    "avatars": avatars,
                    "names": names,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: document)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        observe(document)
    }

    private func removePlayer(_ playerID: String, fromRoomCode roomCode: String) async {
        let document = database.collection("rooms").document(roomCode)
        do {
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let snapshot = try transaction.getDocument(document)
                    guard let data = snapshot.data() else { return nil }

                    let status = data["status"] as? String ?? "waiting"
                    let hostID = data["host"] as? String ?? ""
                    let currentMembers = data["members"] as? [String] ?? []
                    let remainingMembers = currentMembers.filter { $0 != playerID }

                    guard !remainingMembers.isEmpty else {
                        transaction.deleteDocument(document)
                        return nil
                    }

                    if status == "waiting" {
                        var avatars = data["avatars"] as? [String: String] ?? [:]
                        var names = data["names"] as? [String: String] ?? [:]
                        avatars[playerID] = nil
                        names[playerID] = nil
                        transaction.updateData([
                            "members": remainingMembers,
                            "avatars": avatars,
                            "names": names,
                            "host": hostID == playerID ? remainingMembers[0] : hostID,
                            "updatedAt": FieldValue.serverTimestamp()
                        ], forDocument: document)
                    } else if hostID == playerID {
                        transaction.updateData([
                            "host": remainingMembers[0],
                            "updatedAt": FieldValue.serverTimestamp()
                        ], forDocument: document)
                    }
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        } catch {
            // The local departure should still succeed if remote cleanup fails.
        }
    }

    private func observe(_ reference: DocumentReference) {
        listener?.remove()
        listener = reference.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = self.firebaseMessage(error)
                    return
                }
                guard let data = snapshot?.data() else {
                    self.errorMessage = "The table no longer exists."
                    self.room = nil
                    return
                }
                await self.refreshRoom(data, reference: reference)
            }
        }
    }

    private func refreshRoom(_ data: [String: Any], reference: DocumentReference) async {
        let members = data["members"] as? [String] ?? []
        let avatars = data["avatars"] as? [String: String] ?? [:]
        let names = data["names"] as? [String: String] ?? [:]
        let revision = data["revision"] as? Int ?? 0
        var session: GameSession?
        if let state = data["state"] as? [String: Any], let playerID {
            let hand = try? await reference.collection("hands").document(playerID).getDocument()
            let tiles = hand?.data()?["tiles"] as? [Int] ?? []
            session = Self.session(from: state, members: members, playerID: playerID, ownTiles: tiles)
        }
        room = OnlineRoom(
            code: reference.documentID,
            hostID: data["host"] as? String ?? "",
            playerIDs: members,
            avatarIndices: members.map { Self.avatarIndex(avatars[$0]) },
            playerNames: members.map { names[$0] ?? "Player" },
            maxPlayers: data["capacity"] as? Int ?? 2,
            isPrivate: !(data["discoverable"] as? Bool ?? false),
            status: data["status"] as? String ?? "waiting",
            revision: revision,
            session: session
        )
        if data["host"] as? String == playerID, data["status"] as? String == "playing" {
            if authoritativeSession == nil {
                let authority = try? await reference.collection("authority").document("state").getDocument()
                if let authorityData = authority?.data() {
                    authoritativeSession = Self.authoritativeSession(from: authorityData, members: members)
                }
            }
            observeActions(roomCode: reference.documentID)
        }
    }

    private func submitAction(type: String, tileID: Int, left: Bool) async {
        guard let room, let playerID else { return }
        do {
            try await database.collection("rooms").document(room.code)
                .collection("actions").document(playerID).setData([
                    "type": type,
                    "tileId": tileID,
                    "left": left,
                    "revision": room.revision,
                    "createdAt": FieldValue.serverTimestamp()
                ])
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    private func observeActions(roomCode: String) {
        guard actionListener == nil else { return }
        actionListener = database.collection("rooms").document(roomCode)
            .collection("actions").addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                for change in snapshot?.documentChanges ?? [] where change.type == .added {
                    Task { @MainActor in
                        await self.processAction(change.document, roomCode: roomCode)
                    }
                }
            }
    }

    private func processAction(_ document: QueryDocumentSnapshot, roomCode: String) async {
        guard let room, room.code == roomCode, room.hostID == playerID,
              var session = authoritativeSession,
              document.data()["revision"] as? Int == room.revision,
              room.playerIDs.indices.contains(session.game.turn),
              room.playerIDs[session.game.turn] == document.documentID else {
            try? await document.reference.delete()
            return
        }
        let data = document.data()
        let type = data["type"] as? String ?? ""
        var changed = false
        if type == "play", let tileID = data["tileId"] as? Int {
            changed = session.play(tileID: tileID, on: (data["left"] as? Bool ?? false) ? .left : .right)
        } else if type == "draw" {
            changed = session.drawOrPass()
        } else if type == "next" {
            session.startNextRound()
            changed = true
        } else if type == "rematch" {
            session = GameSession(players: room.playerIDs.count, difficulty: .medium, targetScore: 100, isBlockGame: false)
            changed = true
        }
        if changed {
            authoritativeSession = session
            await publish(session, revision: room.revision + 1)
        }
        try? await document.reference.delete()
    }

    private func publish(_ session: GameSession, revision: Int, starting: Bool = false) async {
        guard let room else { return }
        let reference = database.collection("rooms").document(room.code)
        let publicState = Self.stateData(session, includePrivate: false)
        let authorityState = Self.stateData(session, includePrivate: true)
        let batch = database.batch()
        var roomUpdate: [String: Any] = [
            "revision": revision,
            "state": publicState,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if starting { roomUpdate["status"] = "playing" }
        batch.updateData(roomUpdate, forDocument: reference)
        batch.setData(authorityState, forDocument: reference.collection("authority").document("state"))
        for (index, uid) in room.playerIDs.enumerated() where session.game.hands.indices.contains(index) {
            batch.setData([
                "revision": revision,
                "tiles": session.game.hands[index].map(Self.tileCode)
            ], forDocument: reference.collection("hands").document(uid))
        }
        do {
            try await batch.commit()
        } catch {
            errorMessage = firebaseMessage(error)
        }
    }

    private static func stateData(_ session: GameSession, includePrivate: Bool) -> [String: Any] {
        let game = session.game
        let opening = openingTile(in: game.hands)
        var data: [String: Any] = [
            "protocol": 1,
            "matchId": session.matchID.uuidString,
            "round": session.round,
            "target": session.targetScore,
            "block": session.isBlockGame,
            "scores": session.scores,
            "board": game.board.map(tileCode),
            "counts": game.hands.map(\.count),
            "stockCount": game.stock.count,
            "turn": game.turn,
            "passes": game.consecutivePasses,
            "winner": game.winner ?? -1,
            "award": game.award,
            "finished": game.isFinished,
            "opening": opening
        ]
        if includePrivate {
            data["hands"] = Dictionary(uniqueKeysWithValues: game.hands.enumerated().map {
                (String($0.offset), ["tiles": $0.element.map(tileCode)])
            })
            data["stock"] = game.stock.map(tileCode)
        }
        return data
    }

    private static func session(from state: [String: Any], members: [String], playerID: String, ownTiles: [Int]) -> GameSession? {
        guard let index = members.firstIndex(of: playerID) else { return nil }
        let counts = state["counts"] as? [Int] ?? Array(repeating: 0, count: members.count)
        var hands = counts.map { Array(repeating: DominoTile(first: 0, second: 0), count: $0) }
        if hands.indices.contains(index) { hands[index] = ownTiles.map(tile) }
        let game = DominoGame(
            hands: hands,
            stock: Array(repeating: DominoTile(first: 0, second: 0), count: state["stockCount"] as? Int ?? 0),
            board: (state["board"] as? [Int] ?? []).map(tile),
            turn: state["turn"] as? Int ?? 0,
            consecutivePasses: state["passes"] as? Int ?? 0,
            winner: (state["winner"] as? Int).flatMap { $0 < 0 ? nil : $0 },
            award: state["award"] as? Int ?? 0,
            isFinished: state["finished"] as? Bool ?? false,
            isBlockGame: state["block"] as? Bool ?? false,
            openingTileID: state["opening"] as? Int ?? -1
        )
        return GameSession(game: game, scores: state["scores"] as? [Int] ?? [], targetScore: state["target"] as? Int ?? 100, isBlockGame: state["block"] as? Bool ?? false, round: state["round"] as? Int ?? 1, matchID: state["matchId"] as? String ?? "", didAwardRound: state["finished"] as? Bool ?? false)
    }

    private static func authoritativeSession(from data: [String: Any], members: [String]) -> GameSession? {
        let rawHands = data["hands"] as? [String: Any] ?? [:]
        let hands = members.indices.map { index -> [DominoTile] in
            let wrapper = rawHands[String(index)] as? [String: Any]
            return (wrapper?["tiles"] as? [Int] ?? []).map(tile)
        }
        let game = DominoGame(hands: hands, stock: (data["stock"] as? [Int] ?? []).map(tile), board: (data["board"] as? [Int] ?? []).map(tile), turn: data["turn"] as? Int ?? 0, consecutivePasses: data["passes"] as? Int ?? 0, winner: (data["winner"] as? Int).flatMap { $0 < 0 ? nil : $0 }, award: data["award"] as? Int ?? 0, isFinished: data["finished"] as? Bool ?? false, isBlockGame: data["block"] as? Bool ?? false, openingTileID: data["opening"] as? Int ?? -1)
        return GameSession(game: game, scores: data["scores"] as? [Int] ?? [], targetScore: data["target"] as? Int ?? 100, isBlockGame: data["block"] as? Bool ?? false, round: data["round"] as? Int ?? 1, matchID: data["matchId"] as? String ?? "", didAwardRound: data["finished"] as? Bool ?? false)
    }

    private static func tileCode(_ tile: DominoTile) -> Int { tile.first * 7 + tile.second }
    private static func tile(_ code: Int) -> DominoTile { DominoTile(first: code / 7, second: code % 7) }
    private static func openingTile(in hands: [[DominoTile]]) -> Int {
        hands.flatMap { $0 }.max { lhs, rhs in
            (lhs.isDouble ? 100 + lhs.first : lhs.points) < (rhs.isDouble ? 100 + rhs.first : rhs.points)
        }.map(tileCode) ?? -1
    }

    private func firebaseMessage(_ error: Error) -> String {
        if let onlineError = error as? OnlineGameError {
            return onlineError.description
        }
        return "Firebase : \(error.localizedDescription)"
    }

    private static func makeCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).compactMap { _ in alphabet.randomElement() })
    }

    private static func avatarID(_ index: Int) -> String {
        String(format: "classic_%02d", max(0, index) + 1)
    }

    private func playerProfile(_ uid: String) async throws -> (name: String, avatarID: String) {
        let snapshot = try await database.collection("profiles").document(uid).getDocument()
        guard let data = snapshot.data(),
              let name = data["username"] as? String,
              let avatarID = data["avatarId"] as? String else {
            throw OnlineGameError.message("Save your username in My Profile before playing online.")
        }
        return (name, avatarID)
    }

    private static func avatarIndex(_ id: String?) -> Int {
        guard let id, let number = Int(id.split(separator: "_").last ?? "1") else { return 0 }
        return max(0, number - 1)
    }
}

private enum OnlineGameError: LocalizedError {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): text
        }
    }

    var errorDescription: String? { description }
}

struct OnlineGameView: View {
    let model: AppModel
    @State private var selectedTileID: DominoTile.ID?

    private var online: OnlineGameService {
        model.online
    }

    var body: some View {
        if let room = online.room, let session = room.session, let playerIndex = online.playerIndex {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    OnlineTableCanvas(
                        room: room,
                        session: session,
                        playerIndex: playerIndex,
                        selectedTileID: $selectedTileID,
                        leave: {
                            online.leaveRoom()
                            model.navigate(to: .online)
                        },
                        play: playSelected,
                        drawOrPass: {
                            Task { await online.drawOrPass() }
                        },
                        nextRound: {
                            Task {
                                if session.matchWinner == nil {
                                    await online.startNextRound()
                                } else {
                                    await online.startNewMatch()
                                }
                            }
                        }
                    )
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height - 50,
                        alignment: .top
                    )

                    AdMobBannerView(width: proxy.size.width)
                        .frame(width: proxy.size.width, height: 50)
                        .background(Color.white)
                        .clipped()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onAppear {
                AppOrientation.request(.landscapeRight)
            }
            .onDisappear {
                AppOrientation.request(.portrait)
            }
            .alert("Connection", isPresented: errorBinding) {
                Button("OK", action: online.clearError)
            } message: {
                Text(online.errorMessage ?? "")
            }
        } else {
            Text("Connecting to the table…")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.35))
        }
    }

    private func onlineHeader(room: OnlineRoom, session: GameSession) -> some View {
        HStack {
            Button {
                online.leaveRoom()
                model.navigate(to: .online)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.55), in: .circle)
            }
            Spacer()
            VStack {
                Text("TABLE \(room.code)").font(.headline)
                Text("Player \((online.playerIndex ?? 0) + 1) · Player \(session.game.turn + 1)’s turn")
                    .font(.caption)
            }
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
    }

    private func board(session: GameSession) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                if session.game.board.isEmpty {
                    Text("The player with the highest domino starts.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.game.board) { tile in
                        DominoTileView(tile: tile, width: 38)
                    }
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func playerControls(session: GameSession, playerIndex: Int) -> some View {
        if session.game.isFinished {
            VStack(spacing: 12) {
                Text(resultText(session: session, playerIndex: playerIndex))
                    .font(.title2.bold())
                Button(session.matchWinner == nil ? "Next round" : "New game") {
                    Task {
                        if session.matchWinner == nil {
                            await online.startNextRound()
                        } else {
                            await online.startNewMatch()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        } else {
            Text(session.game.turn == playerIndex ? "Your turn" : "Waiting for player \(session.game.turn + 1)…")
                .font(.headline)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(session.game.hands[playerIndex]) { tile in
                        DominoTileView(
                            tile: tile,
                            isSelected: selectedTileID == tile.id,
                            width: 44
                        )
                        .offset(y: selectedTileID == tile.id ? -8 : 0)
                        .onTapGesture {
                            guard session.game.turn == playerIndex else { return }
                            selectedTileID = selectedTileID == tile.id ? nil : tile.id
                        }
                    }
                }
                .padding(.top, 10)
            }
            .scrollIndicators(.hidden)

            HStack {
                Button("Left") {
                    playSelected(side: .left)
                }
                Button(session.isBlockGame || session.game.stock.isEmpty ? "Pass" : "Draw") {
                    Task { await online.drawOrPass() }
                }
                .disabled(session.game.turn != playerIndex || session.game.canCurrentPlayerPlay())
                Button("Right") {
                    playSelected(side: .right)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.game.turn != playerIndex)
        }
    }

    private func playSelected(side: BoardSide) {
        guard let selectedTileID else { return }
        self.selectedTileID = nil
        Task {
            await online.play(tileID: selectedTileID, side: side)
        }
    }

    private func resultText(session: GameSession, playerIndex: Int) -> String {
        guard let winner = session.game.winner else { return "Drawn round" }
        return winner == playerIndex ? "You win!" : "Player \(winner + 1) wins"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { online.errorMessage != nil },
            set: { if !$0 { online.clearError() } }
        )
    }
}
