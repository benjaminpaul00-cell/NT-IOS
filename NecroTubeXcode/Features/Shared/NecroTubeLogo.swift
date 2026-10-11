import SwiftUI

struct NecroTubeLogo: View {
    var body: some View {
        Image("NecroTubeLogo")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .clipped()
            .accessibilityLabel("NecroTube")
    }
}
