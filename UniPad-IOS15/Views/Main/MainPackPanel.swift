import SwiftUI

struct MainPackPanel: View {
    let item: UniPackItem
    var onBookmarkToggle: () -> Void
    var onDelete: () -> Void
    var onYouTube: () -> Void
    var onWebsite: (() -> Void)?

    @State private var fileSizeString = ""

    private var unipack: UniPack { item.unipack }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        return Self.dateFormatter.string(from: date)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: onBookmarkToggle) {
                        Image(systemName: item.isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: 0x555555))
                    }
                    .frame(width: 40, height: 40)

                    Spacer()

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: 0x555555))
                    }
                    .frame(width: 40, height: 40)
                }

                MarqueeText(
                    text: unipack.title,
                    font: .system(size: 16),
                    color: Color(hex: 0x1A1A1A),
                    fontSize: 16
                )

                HStack {
                    MarqueeText(
                        text: unipack.producerName,
                        font: .system(size: 12),
                        color: Color(hex: 0x666666)
                    )

                    Spacer()

                    Button(action: onYouTube) {
                        Image(systemName: "play.rectangle")
                            .foregroundColor(Color(hex: 0x555555))
                    }
                    .frame(width: 32, height: 32)

                    if let onWebsite, unipack.website != nil {
                        Button(action: onWebsite) {
                            Image(systemName: "globe")
                                .foregroundColor(Color(hex: 0x555555))
                        }
                        .frame(width: 32, height: 32)
                    }
                }

                Spacer().frame(height: 8)

                HStack(alignment: .center) {
                    VStack {
                        Text(NSLocalizedString("MPP_playCount", comment: ""))
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: 0x888888))

                        Text("\(item.openCount)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: 0x1A1A1A))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        DateRow(
                            label: NSLocalizedString("MPP_downloadedDate", comment: ""),
                            value: formatDate(item.createdAt)
                        )
                        DateRow(
                            label: NSLocalizedString("MPP_lastPlayed", comment: ""),
                            value: formatDate(item.lastOpenedAt)
                        )
                    }
                }

                Spacer().frame(height: 8)

                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        PropertyBlock(
                            icon: "square.grid.3x3",
                            title: NSLocalizedString("MPP_padSize", comment: ""),
                            value: "\(unipack.buttonX) × \(unipack.buttonY)"
                        )
                        PropertyBlock(
                            icon: "link",
                            title: NSLocalizedString("MPP_chain", comment: ""),
                            value: "\(unipack.chain)"
                        )
                    }

                    HStack(spacing: 2) {
                        PropertyBlock(
                            icon: "music.note",
                            title: NSLocalizedString("MPP_soundFiles", comment: ""),
                            value: unipack.detailLoaded
                                ? "\(unipack.soundCount)"
                                : NSLocalizedString("measuring", comment: "")
                        )
                        PropertyBlock(
                            icon: "lightbulb",
                            title: NSLocalizedString("MPP_ledEvents", comment: ""),
                            value: unipack.detailLoaded
                                ? "\(unipack.ledTableCount)"
                                : NSLocalizedString("measuring", comment: "")
                        )
                    }
                }

                Spacer()

                if !fileSizeString.isEmpty {
                    HStack {
                        Spacer()
                        Text(fileSizeString)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: 0x888888))
                    }
                }
            }
            .padding(16)
        }
        .task(id: item.id) {
            fileSizeString = ""

            let url = URL(fileURLWithPath: unipack.getPathString())
            let bytes = await FileManagerExtensions.getFolderSize(at: url)

            guard !Task.isCancelled else { return }

            if bytes > 0 {
                fileSizeString = String(
                    format: "%.1f MB",
                    Double(bytes) / 1_048_576.0
                )
            }
        }
    }
}

private struct DateRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: 0x888888))
            Text(value)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: 0x333333))
        }
    }
}

private struct PropertyBlock: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: 0x888888))
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: 0x888888))
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0x1A1A1A))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(hex: 0xF2F2F2))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
