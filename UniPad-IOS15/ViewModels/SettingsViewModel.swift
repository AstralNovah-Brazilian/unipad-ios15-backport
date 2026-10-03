import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    enum Category {
        case info
        case storage
    }

    struct CommunityLink: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let url: String
        let iconName: String

        init(title: String, subtitle: String, url: String, iconName: String) {
            id = url
            self.title = title
            self.subtitle = subtitle
            self.url = url
            self.iconName = iconName
        }
    }

    @Published var selectedCategory: Category = .info
    @Published var unipackCount = 0
    @Published var storageUsed = ""

    private var storageRefreshTask: Task<Void, Never>?

    var appVersionInfo: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        return "UniPad \(version) (\(build))"
    }

    let communityLinks: [CommunityLink] = [
        CommunityLink(
            title: NSLocalizedString("officialHomepage", comment: ""),
            subtitle: NSLocalizedString("officialHomepage_", comment: ""),
            url: "https://unipad.io",
            iconName: "globe"
        ),
        CommunityLink(
            title: NSLocalizedString("officialFacebook", comment: ""),
            subtitle: NSLocalizedString("officialFacebook_", comment: ""),
            url: "https://www.facebook.com/playunipad",
            iconName: "person.2"
        ),
        CommunityLink(
            title: NSLocalizedString("facebookCommunity", comment: ""),
            subtitle: NSLocalizedString("facebookCommunity_", comment: ""),
            url: "https://www.facebook.com/groups/playunipad",
            iconName: "person.3"
        ),
        CommunityLink(
            title: NSLocalizedString("naverCafe", comment: ""),
            subtitle: NSLocalizedString("naverCafe_", comment: ""),
            url: "https://cafe.naver.com/unipad",
            iconName: "cup.and.saucer"
        ),
        CommunityLink(
            title: NSLocalizedString("discord", comment: ""),
            subtitle: NSLocalizedString("discord_", comment: ""),
            url: "https://discord.gg/ESDgyNs",
            iconName: "message"
        ),
        CommunityLink(
            title: NSLocalizedString("kakaotalk", comment: ""),
            subtitle: NSLocalizedString("kakaotalk_", comment: ""),
            url: "https://qr.kakao.com/talk/R4p8KwFLXRZsqEjA1FrAnACDyfc-",
            iconName: "bubble.left"
        ),
        CommunityLink(
            title: NSLocalizedString("email", comment: ""),
            subtitle: NSLocalizedString("email_", comment: ""),
            url: "mailto:0226unipad@gmail.com",
            iconName: "envelope"
        )
    ]

    // MARK: - Storage

    var workspacePath: String {
        WorkspaceManager.shared.downloadWorkspace?.url.path
            ?? "No UniPack folder selected"
    }

    func refreshStorageInfo() {
        let workspaceManager = WorkspaceManager.shared
        let count = workspaceManager.availableWorkspaces.reduce(0) {
            $0 + workspaceManager.getUnipackCount(workspace: $1)
        }

        if unipackCount != count {
            unipackCount = count
        }

        storageRefreshTask?.cancel()
        storageRefreshTask = Task { [weak self] in
            let sizeBytes = await workspaceManager.getAvailableWorkspacesSize()
            guard !Task.isCancelled, let self else { return }

            let value = FileManagerExtensions.byteToMB(sizeBytes) + " MB"
            if storageUsed != value {
                storageUsed = value
            }
        }
    }

    // MARK: - Actions

    func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        PlatformHelpers.openURL(url)
    }

    func openGitHub() {
        openURL("https://github.com/kimjisub/unipad-android")
    }

    func copyFcmToken() async -> String {
        do {
            let token = try await FirebaseManager.shared.messaging.getToken()
            let resolved = token.isEmpty
                ? NSLocalizedString("fcm_token_unavailable", comment: "")
                : token
            PlatformPasteboard.copyString(resolved)
            return resolved
        } catch {
            let fallback = NSLocalizedString("fcm_token_unavailable", comment: "")
            PlatformPasteboard.copyString(fallback)
            return fallback
        }
    }
}
