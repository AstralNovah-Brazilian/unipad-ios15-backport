import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var speed: Double = 30
    var fontSize: CGFloat = 14

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animationTask: Task<Void, Never>?

    private let pauseDuration = 1.5
    private var needsScroll: Bool { textWidth > containerWidth && containerWidth > 0 }
    private var scrollDistance: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .foregroundColor(color)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
                .onAppear {
                    containerWidth = geo.size.width
                    restartAnimation()
                }
                .onChange(of: geo.size.width) { newWidth in
                    containerWidth = newWidth
                    restartAnimation()
                }
        }
        .frame(height: textHeight)
        .clipped()
        .overlay(
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .hidden()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                textWidth = geo.size.width
                                restartAnimation()
                            }
                            .onChange(of: text) { _ in
                                textWidth = geo.size.width
                                restartAnimation()
                            }
                    }
                )
                .frame(width: 0, height: 0)
                .hidden()
        )
        .onChange(of: textWidth) { _ in restartAnimation() }
        .onChange(of: containerWidth) { _ in restartAnimation() }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
            offset = 0
        }
    }

    private var textHeight: CGFloat {
        #if canImport(UIKit)
        return UIFont.systemFont(ofSize: fontSize).lineHeight + 4
        #elseif canImport(AppKit)
        return NSFont.systemFont(ofSize: fontSize).boundingRectForFont.height + 4
        #else
        return fontSize + 4
        #endif
    }

    private func restartAnimation() {
        animationTask?.cancel()
        animationTask = nil
        offset = 0

        guard needsScroll, speed > 0 else { return }

        let distance = scrollDistance
        let duration = Double(distance) / speed
        guard duration > 0 else { return }

        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(pauseDuration * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }

                withAnimation(.linear(duration: duration)) {
                    offset = -distance
                }

                try? await Task.sleep(
                    nanoseconds: UInt64((duration + pauseDuration) * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }

                withAnimation(.linear(duration: duration)) {
                    offset = 0
                }

                try? await Task.sleep(
                    nanoseconds: UInt64(duration * 1_000_000_000)
                )
            }
        }
    }
}
