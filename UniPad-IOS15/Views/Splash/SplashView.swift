import SwiftUI

struct UniPadLogoView: View {
    let size: CGFloat

    var body: some View {
        Image("UniPadIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

struct SplashView: View {
    @EnvironmentObject private var router: AppRouter

    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.8

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ZStack {
            AppColors.background1
                .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(spacing: 12) {
                    UniPadLogoView(size: 70)

                    Text("UniPad")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                .opacity(logoOpacity)
                .scaleEffect(logoScale)

                Spacer()

                VStack(spacing: 5) {
                    Text(versionString)
                        .font(.system(size: 12))
                        .foregroundColor(.white)

                    Text(NSLocalizedString("copyright", comment: ""))
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textPrimary)
                }
                .padding(.bottom, 10)
                .opacity(logoOpacity)
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.6)) {
                logoOpacity = 1
                logoScale = 1
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }

            router.dismissSplash()
        }
    }
}
