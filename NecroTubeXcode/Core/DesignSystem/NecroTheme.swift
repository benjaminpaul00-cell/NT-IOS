import SwiftUI

enum NecroTheme {
    static let background = Color.black
    static let panel = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let raisedPanel = Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)
    static let border = Color.white.opacity(0.30)
    static let accent = Color(red: 0, green: 230 / 255, blue: 118 / 255)
    static let gold = Color(red: 1, green: 215 / 255, blue: 0)
    static let danger = Color.red
    static let muted = Color(red: 136 / 255, green: 136 / 255, blue: 136 / 255)
}

extension View {
    func necroPanel(cornerRadius: CGFloat = 14) -> some View {
        background(NecroTheme.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).stroke(NecroTheme.border) }
    }
}
