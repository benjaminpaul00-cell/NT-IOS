import SwiftUI

struct AvatarCatalogView: View {
    let index: Int
    var size: CGFloat = 80

    var body: some View {
        let safeIndex = min(49, max(0, index))
        let column = safeIndex % 10
        let row = safeIndex / 10

        Image("AvatarCatalog")
            .resizable()
            .frame(width: size * 10.2, height: size * 5.1)
            .offset(
                x: -(0.126 + CGFloat(column) * 1.02) * size,
                y: -(0.063 + CGFloat(row) * 1.02) * size
            )
            .frame(width: size, height: size, alignment: .topLeading)
            .clipped()
            .clipShape(.circle)
            .contentShape(Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Avatar \(safeIndex + 1)")
    }
}

struct AvatarPickerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftIndex: Int
    @State private var page: Int

    init(model: AppModel) {
        self.model = model
        _draftIndex = State(initialValue: model.selectedAvatarIndex)
        _page = State(initialValue: model.selectedAvatarIndex / 10)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ZStack {
                    Image("MenuScene")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()

                    let scale = min(proxy.size.width / 480, (proxy.size.height - 60) / 850)
                    AvatarPickerCanvas(
                        draftIndex: $draftIndex,
                        page: $page,
                        cancel: { dismiss() },
                        confirm: {
                            model.selectedAvatarIndex = draftIndex
                            model.performFeedback()
                            dismiss()
                        }
                    )
                    .frame(width: 480, height: 850)
                    .scaleEffect(scale, anchor: .center)
                    .position(
                        x: proxy.size.width / 2,
                        y: 425 * scale
                    )
                }

                AdMobBannerView(width: proxy.size.width)
                    .frame(width: proxy.size.width, height: 63)
                    .background(.white)
                    .clipped()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct AvatarPickerCanvas: View {
    @Binding var draftIndex: Int
    @Binding var page: Int
    let cancel: () -> Void
    let confirm: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(72), spacing: 10), count: 5)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: cancel) {
                Image(systemName: "chevron.left")
                    .font(.title.bold())
                    .frame(width: 54, height: 54)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.45), in: .circle)
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .position(x: 40, y: 44)

            Image("DominoLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 134, height: 100)
                .position(x: 240, y: 65)

            Text("Your character")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .position(x: 240, y: 151)

            Text("50 portraits. Find the one that feels like you.")
                .font(.system(size: 15))
                .foregroundStyle(Color(red: 0.68, green: 0.76, blue: 0.86))
                .position(x: 240, y: 184)

            AvatarCatalogView(index: draftIndex, size: 118)
                .overlay(Circle().stroke(Color(red: 1, green: 0.82, blue: 0.35), lineWidth: 3))
                .position(x: 240, y: 276)

            Text("Avatar \(draftIndex + 1)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.35))
                .position(x: 240, y: 365)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(page * 10..<(page + 1) * 10, id: \.self) { index in
                    Button {
                        draftIndex = index
                    } label: {
                        AvatarCatalogView(index: index, size: 68)
                            .padding(2)
                            .overlay(
                                Circle().stroke(
                                    index == draftIndex
                                        ? Color(red: 1, green: 0.82, blue: 0.35)
                                        : .clear,
                                    lineWidth: 3
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose avatar \(index + 1)")
                }
            }
            .frame(width: 420, height: 190)
            .padding(8)
            .background(Color(red: 0.03, green: 0.1, blue: 0.19).opacity(0.86), in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.2)))
            .position(x: 240, y: 490)

            HStack {
                AvatarPageButton(title: "Previous", enabled: page > 0) {
                    page -= 1
                }
                Spacer()
                Text("\(page + 1) / 5")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                AvatarPageButton(title: "Next", enabled: page < 4) {
                    page += 1
                }
            }
            .frame(width: 416)
            .position(x: 240, y: 640)

            Button(action: confirm) {
                Label("Use this avatar", systemImage: "checkmark")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.22))
                    .frame(width: 360, height: 60)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 1, green: 0.89, blue: 0.4),
                                Color(red: 0.95, green: 0.57, blue: 0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: .capsule
                    )
                    .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 2))
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 5)
            }
            .buttonStyle(.plain)
            .position(x: 240, y: 775)
        }
    }
}

private struct AvatarPageButton: View {
    let title: LocalizedStringKey
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.headline.bold())
            .foregroundStyle(enabled ? .white : .white.opacity(0.45))
            .frame(width: 120, height: 46)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.2, green: 0.31, blue: 0.48),
                        Color(red: 0.08, green: 0.16, blue: 0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: .capsule
            )
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1.5))
            .disabled(!enabled)
    }
}
