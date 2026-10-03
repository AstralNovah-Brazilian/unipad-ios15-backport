import SwiftUI

struct MainTotalPanel: View {
    let openCount: Int
    let unipackCount: Int?
    let unipackCapacity: String?
    let themeName: String?
    let updateAvailable: Bool
    var onSettingsClick: () -> Void
    var onUpdateClick: () -> Void

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Image("UniPadIconTextIntro")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 48)

                Text(versionString)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textPrimary)
            }

            Spacer().frame(height: 12)

            VStack(spacing: 8) {
                StatRow(
                    label: NSLocalizedString("MPT_playCount", comment: ""),
                    value: "\(openCount)"
                )
                StatRow(
                    label: NSLocalizedString("MTP_count", comment: ""),
                    value: unipackCount.map(String.init) ?? "-"
                )
                StatRow(
                    label: NSLocalizedString("MTP_size", comment: ""),
                    value: unipackCapacity.map { "\($0) MB" } ?? "-"
                )

                if let themeName {
                    StatRow(
                        label: NSLocalizedString("MPT_theme", comment: ""),
                        value: themeName
                    )
                }
            }
            .padding(12)
            .background(AppColors.darkSurfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            HStack {
                if updateAvailable {
                    Button(action: onUpdateClick) {
                        Text(NSLocalizedString("update_available", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                Button(action: onSettingsClick) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.textPrimary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.darkSurface)
        )
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
