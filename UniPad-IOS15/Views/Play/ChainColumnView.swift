import SwiftUI

struct ChainBarView: View {
    let axis: Axis
    let chainIndices: [Int]
    let chainColors: [Color]
    let chainItems: [ChannelManager.Item?]
    let visibleChainIndices: Set<Int>
    let cellSize: CGFloat
    let theme: ThemeResourcesProtocol
    let onChainTap: (Int) -> Void

    var body: some View {
        Group {
            switch axis {
            case .vertical:
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 0) { buttons }
                        .frame(
                            width: cellSize,
                            height: cellSize * CGFloat(chainIndices.count),
                            alignment: .center
                        )
                    Spacer(minLength: 0)
                }
            case .horizontal:
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 0) { buttons }
                        .frame(
                            width: cellSize * CGFloat(chainIndices.count),
                            height: cellSize,
                            alignment: .center
                        )
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(chainIndices, id: \.self) { index in
            if visibleChainIndices.contains(index) {
                ChainButtonView(
                    color: index < chainColors.count ? chainColors[index] : .clear,
                    chainItem: index < chainItems.count ? chainItems[index] : nil,
                    theme: theme,
                    onTap: {
                        guard index >= PlayViewModel.chainIndexOffset else { return }
                        onChainTap(index - PlayViewModel.chainIndexOffset)
                    }
                )
                .frame(width: cellSize, height: cellSize)
            } else {
                Color.clear
                    .frame(width: cellSize, height: cellSize)
            }
        }
    }
}

private struct ChainButtonView: View {
    let color: Color
    let chainItem: ChannelManager.Item?
    let theme: ThemeResourcesProtocol
    let onTap: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = max(0, min(geometry.size.width, geometry.size.height) - 2)

            ZStack {
                if theme.isChainLed {
                    if let btn = theme.btn {
                        Image(platformImage: btn)
                            .resizable()
                            .frame(width: size, height: size)
                    }

                    if color != .clear {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: size, height: size)
                    }

                    if let chainled = theme.chainled {
                        Image(platformImage: chainled)
                            .resizable()
                            .frame(width: size, height: size)
                    }
                } else if let image = chainImageForDrawableMode() {
                    Image(platformImage: image)
                        .resizable()
                        .frame(width: size, height: size)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    @inline(__always)
    private func chainImageForDrawableMode() -> PlatformImage? {
        guard let item = chainItem else { return theme.chain }

        switch item.channel {
        case .guide:
            return theme.chainGuide ?? theme.chain
        case .chain:
            return theme.chainSelected ?? theme.chain
        default:
            return theme.chain
        }
    }
}
