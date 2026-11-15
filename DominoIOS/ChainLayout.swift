import Foundation
import SwiftUI

struct ChainPlacement: Identifiable {
    let tile: DominoTile
    let center: CGPoint
    let direction: CGVector
    let angle: Angle
    let cellWidth: CGFloat
    let cellHeight: CGFloat

    var id: DominoTile.ID { tile.id }
}

enum ChainLayout {
    static func build(for tiles: [DominoTile]) -> [ChainPlacement] {
        guard !tiles.isEmpty else { return [] }

        for height in stride(from: 6, through: 16, by: 2) {
            var placements: [ChainPlacement] = []
            var budget = 30_000
            if place(
                tiles: tiles,
                index: 0,
                endX: -10,
                endY: -CGFloat(height) / 2 + 1,
                dx: 1,
                dy: 0,
                width: 22,
                height: CGFloat(height),
                placements: &placements,
                budget: &budget
            ) {
                return placements
            }
        }

        var endX: CGFloat = 0
        return tiles.map { tile in
            let centerX = endX + (tile.isDouble ? 1 : 1.5)
            endX = tile.isDouble ? centerX : centerX + 0.5
            return placement(tile: tile, x: centerX, y: 0, dx: 1, dy: 0)
        }
    }

    private static func place(
        tiles: [DominoTile],
        index: Int,
        endX: CGFloat,
        endY: CGFloat,
        dx: Int,
        dy: Int,
        width: CGFloat,
        height: CGFloat,
        placements: inout [ChainPlacement],
        budget: inout Int
    ) -> Bool {
        guard index < tiles.count else { return true }
        budget -= 1
        guard budget >= 0 else { return false }

        for direction in [(dx, dy), (-dy, dx), (dy, -dx)] {
            let tile = tiles[index]
            let cross = tile.isDouble
            let firstX = endX + CGFloat(direction.0)
            let firstY = endY + CGFloat(direction.1)
            let centerX = firstX + (cross ? 0 : CGFloat(direction.0) * 0.5)
            let centerY = firstY + (cross ? 0 : CGFloat(direction.1) * 0.5)
            let candidate = placement(tile: tile, x: centerX, y: centerY, dx: direction.0, dy: direction.1)

            guard centerX - candidate.cellWidth / 2 >= -width / 2,
                  centerX + candidate.cellWidth / 2 <= width / 2,
                  centerY - candidate.cellHeight / 2 >= -height / 2,
                  centerY + candidate.cellHeight / 2 <= height / 2,
                  !placements.contains(where: { overlaps(candidate, $0) }) else {
                continue
            }

            placements.append(candidate)
            let nextX = centerX + (cross ? 0 : CGFloat(direction.0) * 0.5)
            let nextY = centerY + (cross ? 0 : CGFloat(direction.1) * 0.5)
            if place(
                tiles: tiles,
                index: index + 1,
                endX: nextX,
                endY: nextY,
                dx: direction.0,
                dy: direction.1,
                width: width,
                height: height,
                placements: &placements,
                budget: &budget
            ) {
                return true
            }
            placements.removeLast()
        }
        return false
    }

    private static func placement(tile: DominoTile, x: CGFloat, y: CGFloat, dx: Int, dy: Int) -> ChainPlacement {
        let isVertical = (dy != 0) != tile.isDouble
        let angle: Angle
        if tile.isDouble {
            angle = .degrees(dy != 0 ? 90 : 0)
        } else if dx == 1 {
            angle = .degrees(-90)
        } else if dx == -1 {
            angle = .degrees(90)
        } else if dy == 1 {
            angle = .zero
        } else {
            angle = .degrees(180)
        }
        return ChainPlacement(
            tile: tile,
            center: CGPoint(x: x, y: y),
            direction: CGVector(dx: dx, dy: dy),
            angle: angle,
            cellWidth: isVertical ? 1 : 2,
            cellHeight: isVertical ? 2 : 1
        )
    }

    private static func overlaps(_ first: ChainPlacement, _ second: ChainPlacement) -> Bool {
        abs(first.center.x - second.center.x) < (first.cellWidth + second.cellWidth) / 2 - 0.01 &&
            abs(first.center.y - second.center.y) < (first.cellHeight + second.cellHeight) / 2 - 0.01
    }
}
