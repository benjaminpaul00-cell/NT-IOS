import SwiftUI

struct DominoTileView: View {
    let tile: DominoTile
    var isSelected = false
    var isFaceDown = false
    var width: CGFloat = 50

    private var cornerRadius: CGFloat {
        max(4, width * 0.14)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isFaceDown {
                RoundedRectangle(cornerRadius: cornerRadius * 0.55)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    .padding(width * 0.12)
            } else {
                PipHalf(value: tile.first, tileWidth: width)
                Rectangle()
                    .fill(Color.black.opacity(0.62))
                    .frame(height: max(1, width * 0.035))
                    .overlay(Color.white.opacity(0.38).frame(height: 1), alignment: .bottom)
                PipHalf(value: tile.second, tileWidth: width)
            }
        }
        .frame(width: width, height: width * 1.965)
        .background {
            if isFaceDown {
                LinearGradient(
                    colors: [
                        Color(red: 0.88, green: 0.83, blue: 0.82),
                        Color(red: 0.55, green: 0.47, blue: 0.47)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Image("TileFace")
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .brightness(isSelected ? 0.16 : 0)
        .shadow(
            color: isSelected ? Color.yellow.opacity(0.72) : Color.black.opacity(0.65),
            radius: isSelected ? max(8, width * 0.22) : max(2, width * 0.08),
            x: isSelected ? 0 : 1,
            y: isSelected ? 0 : max(2, width * 0.08)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFaceDown ? "Hidden domino" : "Domino \(tile.first), \(tile.second)")
    }
}

private struct PipHalf: View {
    let value: Int
    let tileWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let dx = tileWidth * 0.23
            let dy = tileWidth * 0.24
            let radius = tileWidth * 0.081
            var points: [CGPoint] = []

            if value.isMultiple(of: 2) == false {
                points.append(center)
            }
            if value >= 2 {
                points.append(CGPoint(x: center.x - dx, y: center.y - dy))
                points.append(CGPoint(x: center.x + dx, y: center.y + dy))
            }
            if value >= 4 {
                points.append(CGPoint(x: center.x + dx, y: center.y - dy))
                points.append(CGPoint(x: center.x - dx, y: center.y + dy))
            }
            if value == 6 {
                points.append(CGPoint(x: center.x - dx, y: center.y))
                points.append(CGPoint(x: center.x + dx, y: center.y))
            }

            for point in points {
                let highlight = CGRect(
                    x: point.x - radius * 1.15,
                    y: point.y - radius * 1.15,
                    width: radius * 2.3,
                    height: radius * 2.3
                )
                context.fill(Path(ellipseIn: highlight), with: .color(Color(red: 1, green: 0.97, blue: 0.86)))

                let pip = CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(
                    Path(ellipseIn: pip),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 0.19, green: 0.19, blue: 0.17),
                            Color(red: 0.03, green: 0.04, blue: 0.05)
                        ]),
                        center: CGPoint(x: point.x - radius * 0.25, y: point.y - radius * 0.25),
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
        .frame(maxHeight: .infinity)
    }
}
