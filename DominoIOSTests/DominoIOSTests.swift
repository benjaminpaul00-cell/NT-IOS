import Foundation
import Testing
@testable import DominoIOS

struct DominoGameTests {
    @Test func createsCompleteDoubleSixSetAcrossHandsAndStock() {
        var generator = SeededGenerator(seed: 42)
        let game = DominoGame(players: 2, isBlockGame: false, using: &generator)
        let tiles = game.hands.flatMap { $0 } + game.stock

        #expect(tiles.count == 28)
        #expect(Set(tiles).count == 28)
        #expect(tiles.allSatisfy { (0...6).contains($0.first) && (0...6).contains($0.second) })
    }

    @Test func drawDealsSevenTilesToEveryPlayer() {
        var generator = SeededGenerator(seed: 7)
        let game = DominoGame(players: 4, isBlockGame: false, using: &generator)

        #expect(game.hands.map(\.count) == [7, 7, 7, 7])
        #expect(game.stock.isEmpty)
    }

    @Test func blockDealsFiveTilesWithThreeOrFourPlayers() {
        var generator = SeededGenerator(seed: 9)
        let game = DominoGame(players: 3, isBlockGame: true, using: &generator)

        #expect(game.hands.map(\.count) == [5, 5, 5])
        #expect(game.stock.count == 13)
    }

    @Test func openingPlayerCanOnlyPlayOpeningTile() {
        var generator = SeededGenerator(seed: 18)
        let game = DominoGame(players: 2, isBlockGame: false, using: &generator)
        let legalTiles = game.hands[game.turn].filter {
            game.isLegal($0, on: .left) || game.isLegal($0, on: .right)
        }

        #expect(legalTiles.count == 1)
    }

    @Test func chainLayoutKeepsOnePlacementPerTile() {
        let tiles = [
            DominoTile(first: 6, second: 6),
            DominoTile(first: 6, second: 4),
            DominoTile(first: 4, second: 2),
            DominoTile(first: 2, second: 2),
            DominoTile(first: 2, second: 0)
        ]
        let placements = ChainLayout.build(for: tiles)

        #expect(placements.count == tiles.count)
        #expect(Set(placements.map(\.id)).count == tiles.count)
    }

    @Test func sessionStartsWithZeroScores() {
        let session = GameSession(players: 4, difficulty: .hard, targetScore: 150, isBlockGame: true)

        #expect(session.scores == [0, 0, 0, 0])
        #expect(session.targetScore == 150)
        #expect(session.difficulty == .hard)
        #expect(session.isBlockGame)
    }

    @Test func finishedRoundIsAwardedOnlyOnce() {
        let winningTile = DominoTile(first: 6, second: 6)
        let game = DominoGame(
            hands: [[winningTile], [DominoTile(first: 1, second: 2)]],
            stock: [],
            board: [],
            turn: 0,
            consecutivePasses: 0,
            winner: nil,
            award: 0,
            isFinished: false,
            isBlockGame: true,
            openingTileID: winningTile.id
        )
        var session = GameSession(
            game: game,
            scores: [0, 0],
            targetScore: 100,
            isBlockGame: true,
            round: 1,
            matchID: UUID().uuidString,
            didAwardRound: false
        )

        #expect(session.play(tileID: winningTile.id, on: .left))
        #expect(session.scores == [3, 0])

        session.settleRound()
        #expect(session.scores == [3, 0])
    }

    @Test func blockedRoundChoosesLowestHand() {
        var game = DominoGame(
            hands: [
                [DominoTile(first: 0, second: 0)],
                [DominoTile(first: 1, second: 1)]
            ],
            stock: [],
            board: [DominoTile(first: 6, second: 6)],
            turn: 0,
            consecutivePasses: 0,
            winner: nil,
            award: 0,
            isFinished: false,
            isBlockGame: true,
            openingTileID: DominoTile(first: 6, second: 6).id
        )

        #expect(game.drawOrPass())
        #expect(game.drawOrPass())
        #expect(game.isFinished)
        #expect(game.winner == 0)
        #expect(game.award == 2)
    }

    @Test @MainActor func savedSessionRoundTripsWithoutLosingState() throws {
        let session = GameSession(
            players: 3,
            difficulty: .hard,
            targetScore: 150,
            isBlockGame: true
        )

        let data = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(GameSession.self, from: data)

        #expect(restored == session)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
