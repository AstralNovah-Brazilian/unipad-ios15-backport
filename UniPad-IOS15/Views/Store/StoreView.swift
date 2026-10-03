import SwiftUI

struct StoreView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = StoreViewModel()
    @State private var showDownloadingGuardAlert = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                leftPanel
                    .frame(width: geometry.size.width * 0.4)
                rightPanel
                    .frame(width: geometry.size.width * 0.6)
            }
        }
        .background(AppColors.background1)
        .platformNavigationBarHidden(true)
        .onAppear {
            vm.loadStore()
        }
        .alert(NSLocalizedString("warning", comment: ""), isPresented: $showDownloadingGuardAlert) {
            Button(NSLocalizedString("accept", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("canNotQuitWhileDownloading", comment: ""))
        }
    }

    // MARK: - Left Panel

    @ViewBuilder
    private var leftPanel: some View {
        VStack {
            Group {
                if let selected = vm.selectedItem {
                    StorePackPanel(
                        item: selected,
                        onDownload: { vm.startDownload(selected) },
                        onYouTube: { vm.openYouTubeSearch(for: selected) }
                    )
                    .transition(.opacity)
                } else {
                    StoreTotalPanel(
                        storeCount: vm.storeItems.count,
                        downloadedCount: vm.downloadedCount
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: vm.selectedItem?.id)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 0))
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if vm.storeItems.contains(where: { $0.downloading }) {
                        showDownloadingGuardAlert = true
                    } else {
                        router.pop()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.white)
                        .font(.system(size: 18))
                }
                .padding(.leading, 4)

                Image(systemName: "cart")
                    .foregroundStyle(AppColors.skyblue)
                    .font(.system(size: 20))

                Text(NSLocalizedString("store", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Text("\(vm.storeItems.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()
            }
            .padding(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 16))

            if vm.storeItems.isEmpty {
                Spacer()

                if vm.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 80))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(NSLocalizedString("UnableToAccessServer", comment: ""))
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }

                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.storeItems) { item in
                            StoreListItemView(
                                item: item,
                                onTap: { vm.toggleSelection(item) },
                                onFlagTap: {
                                    if !item.downloaded && !item.downloading {
                                        vm.startDownload(item)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                }
            }
        }
    }
}

// MARK: - Store List Item

private struct StoreListItemView: View {
    let item: StoreViewModel.StoreItem
    var onTap: () -> Void
    var onFlagTap: () -> Void

    private var defaultColor: Color {
        item.downloaded ? AppColors.green : AppColors.red
    }

    private var flagColor: Color {
        item.flagColorOverride ?? defaultColor
    }

    var body: some View {
        UnipackListItemView(
            title: item.title,
            subtitle: item.producerName,
            hasLed: item.isLED,
            hasAutoPlay: item.isAutoPlay,
            isBookmarked: false,
            isSelected: item.isToggle,
            flagColor: flagColor,
            flagText: item.downloading
                ? item.playText
                : (item.isToggle
                    ? (item.downloaded
                        ? NSLocalizedString("downloaded", comment: "")
                        : NSLocalizedString("download", comment: ""))
                    : nil),
            flagExpandedWidth: 100,
            indicatorFontSize: 12,
            onTap: onTap,
            onPlay: onFlagTap
        )
    }
}

// MARK: - Store Total Panel

private struct StoreTotalPanel: View {
    let storeCount: Int
    let downloadedCount: Int

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.darkSurface)

            VStack(spacing: 8) {
                Spacer()

                Image(systemName: "cart")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.skyblue)

                Text(NSLocalizedString("store", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text(versionString)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer().frame(height: 16)

                VStack(spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("STP_count", comment: ""))
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(storeCount)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    HStack {
                        Text(NSLocalizedString("STP_downloadedCount", comment: ""))
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(downloadedCount)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(12)
                .background(AppColors.darkSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: - Store Pack Panel

private struct StorePackPanel: View {
    let item: StoreViewModel.StoreItem
    var onDownload: () -> Void
    var onYouTube: () -> Void

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private var progress: Double {
        parseProgress(item.playText)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)

            VStack(alignment: .leading, spacing: 0) {
                MarqueeText(
                    text: item.title,
                    font: .system(size: 16, weight: .bold),
                    color: Color(hex: 0x1A1A1A),
                    fontSize: 16
                )

                HStack {
                    MarqueeText(
                        text: item.producerName,
                        font: .system(size: 12),
                        color: Color(hex: 0x666666)
                    )

                    Spacer()

                    Button(action: onYouTube) {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(Color(hex: 0x555555))
                    }
                }

                Spacer().frame(height: 12)

                HStack(spacing: 8) {
                    FeatureBadge(label: "LED", enabled: item.isLED)
                    FeatureBadge(label: "AUTOPLAY", enabled: item.isAutoPlay)
                }

                Spacer().frame(height: 12)

                VStack(spacing: 4) {
                    HStack {
                        Text(NSLocalizedString("SPP_downloadCount", comment: ""))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: 0x888888))

                        Spacer()

                        Text(Self.numberFormatter.string(from: NSNumber(value: item.downloadCount)) ?? "\(item.downloadCount)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1A1A1A))
                    }

                    if item.fileSize > 0 {
                        HStack {
                            Text(NSLocalizedString("MPP_fileSize", comment: ""))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: 0x888888))

                            Spacer()

                            Text(String(format: "%.2f MB", Double(item.fileSize) / 1_048_576.0))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(hex: 0x1A1A1A))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(hex: 0xF2F2F2))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                if item.downloading {
                    ProgressView(value: progress)
                        .tint(AppColors.blue)
                        .background(Color(hex: 0xE0E0E0))
                        .frame(height: 6)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .animation(.easeInOut(duration: 0.3), value: progress)

                    Text(item.playText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0x888888))
                } else if item.downloaded {
                    Text(NSLocalizedString("downloaded", comment: ""))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x4CAF50))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xE8F5E9))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Button(action: onDownload) {
                        Text(NSLocalizedString("download", comment: ""))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(AppColors.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(16)
        }
    }

    private func parseProgress(_ text: String) -> Double {
        guard let match = text.range(of: #"^(\d+)%"#, options: .regularExpression) else { return 0 }
        let numStr = text[match].dropLast()
        return (Double(numStr) ?? 0) / 100.0
    }
}

private struct FeatureBadge: View {
    let label: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(enabled ? Color(hex: 0x4CAF50) : Color(hex: 0xE91E63))
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(enabled ? Color(hex: 0x388E3C) : Color(hex: 0xC2185B))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(enabled ? Color(hex: 0xE8F5E9) : Color(hex: 0xFCE4EC))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
