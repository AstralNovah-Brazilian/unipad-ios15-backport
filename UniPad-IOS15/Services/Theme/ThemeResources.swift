import SwiftUI

// MARK: - Theme Metadata

struct ThemeMetadata: Codable {
    let name: String
    let author: String
    var version: String = "1.0"
}

struct ThemeColors: Codable {
    var checkbox: String?
    var traceLog: String?
    var optionWindow: String?
    var optionWindowCheckbox: String?

    enum CodingKeys: String, CodingKey {
        case checkbox
        case traceLog = "trace_log"
        case optionWindow = "option_window"
        case optionWindowCheckbox = "option_window_checkbox"
    }
}

// MARK: - Protocol

protocol ThemeResourcesProtocol {
    var icon: PlatformImage? { get }
    var name: String { get }
    var author: String { get }
    var version: String { get }

    var playbg: PlatformImage? { get }
    var customLogo: PlatformImage? { get }
    var btn: PlatformImage? { get }
    var btnPressed: PlatformImage? { get }
    var chainled: PlatformImage? { get }
    var chain: PlatformImage? { get }
    var chainSelected: PlatformImage? { get }
    var chainGuide: PlatformImage? { get }
    var phantom: PlatformImage? { get }
    var phantomVariant: PlatformImage? { get }
    var isChainLed: Bool { get }

    var checkboxColor: Color { get }
    var traceLogColor: Color { get }
    var optionWindowColor: Color { get }
    var optionWindowCheckboxColor: Color { get }
}

// MARK: - Default Theme

struct DefaultThemeResources: ThemeResourcesProtocol {
    static var displayName: String {
        NSLocalizedString("theme_default_name", comment: "")
    }

    static let displayAuthor = "UniPad dev."

    let icon: PlatformImage? = PlatformImage(named: "theme_ic")
    let name: String = DefaultThemeResources.displayName
    let author: String = DefaultThemeResources.displayAuthor
    let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    let playbg: PlatformImage? = PlatformImage(named: "playbg")
    let customLogo: PlatformImage? = nil
    let btn: PlatformImage? = PlatformImage(named: "btn")
    let btnPressed: PlatformImage? = PlatformImage(named: "btn_pressed")
    let chainled: PlatformImage? = PlatformImage(named: "chainled")
    let chain: PlatformImage? = PlatformImage(named: "chain")
    let chainSelected: PlatformImage? = PlatformImage(named: "chain_selected")
    let chainGuide: PlatformImage? = PlatformImage(named: "chain_guide")
    let phantom: PlatformImage? = PlatformImage(named: "phantom")
    let phantomVariant: PlatformImage? = PlatformImage(named: "phantom_variant")
    let isChainLed = true

    let checkboxColor: Color = AppColors.checkbox
    let traceLogColor: Color = AppColors.traceLog
    let optionWindowColor: Color = AppColors.optionWindow
    let optionWindowCheckboxColor: Color = AppColors.optionWindowCheckbox
}

// MARK: - Folder Theme

struct FolderThemeResources: ThemeResourcesProtocol {
    let icon: PlatformImage?
    let name: String
    let author: String
    let version: String

    let playbg: PlatformImage?
    let customLogo: PlatformImage?
    let btn: PlatformImage?
    let btnPressed: PlatformImage?
    let chainled: PlatformImage?
    let chain: PlatformImage?
    let chainSelected: PlatformImage?
    let chainGuide: PlatformImage?
    let phantom: PlatformImage?
    let phantomVariant: PlatformImage?
    let isChainLed: Bool

    let checkboxColor: Color
    let traceLogColor: Color
    let optionWindowColor: Color
    let optionWindowCheckboxColor: Color

    init(themeDir: URL, fullLoad: Bool = false) throws {
        let files = Self.indexFiles(in: themeDir)

        guard let themeJsonURL = files["theme.json"] else {
            throw ThemeLoadError.metadataNotFound
        }

        let decoder = JSONDecoder()
        let metadata = try decoder.decode(
            ThemeMetadata.self,
            from: Data(contentsOf: themeJsonURL)
        )
        let defaults = DefaultThemeResources()

        var colors: ThemeColors?
        if let colorsURL = files["colors.json"],
           let colorsData = try? Data(contentsOf: colorsURL) {
            colors = try? decoder.decode(ThemeColors.self, from: colorsData)
        }

        name = metadata.name
        author = metadata.author
        version = metadata.version
        icon = Self.loadPng(named: "theme_ic", files: files) ?? defaults.icon

        if fullLoad {
            playbg = Self.loadPng(named: "playbg", files: files) ?? defaults.playbg
            customLogo = Self.loadPng(named: "custom_logo", files: files)
            btn = Self.loadPng(named: "btn", files: files) ?? defaults.btn
            btnPressed = Self.loadAnyPng(
                names: ["btn_", "btn_pressed", "btn-pressed"],
                files: files
            ) ?? defaults.btnPressed

            if let image = Self.loadPng(named: "chainled", files: files) {
                chainled = image
                isChainLed = true
                chain = nil
                chainSelected = nil
                chainGuide = nil
            } else {
                chainled = nil
                isChainLed = false
                chain = Self.loadPng(named: "chain", files: files) ?? defaults.chain
                chainSelected = Self.loadAnyPng(
                    names: ["chain_", "chain_selected"],
                    files: files
                ) ?? defaults.chainSelected
                chainGuide = Self.loadAnyPng(
                    names: ["chain__", "chain_guide"],
                    files: files
                ) ?? defaults.chainGuide
            }

            phantom = Self.loadPng(named: "phantom", files: files) ?? defaults.phantom
            phantomVariant = Self.loadAnyPng(
                names: ["phantom_", "phantom_variant"],
                files: files
            )

            checkboxColor = Self.parseColor(colors?.checkbox) ?? defaults.checkboxColor
            traceLogColor = Self.parseColor(colors?.traceLog) ?? defaults.traceLogColor
            optionWindowColor = Self.parseColor(colors?.optionWindow) ?? defaults.optionWindowColor
            optionWindowCheckboxColor = Self.parseColor(colors?.optionWindowCheckbox) ?? defaults.optionWindowCheckboxColor
        } else {
            playbg = nil
            customLogo = nil
            btn = nil
            btnPressed = nil
            chainled = nil
            chain = nil
            chainSelected = nil
            chainGuide = nil
            phantom = nil
            phantomVariant = nil
            isChainLed = true
            checkboxColor = AppColors.checkbox
            traceLogColor = AppColors.traceLog
            optionWindowColor = AppColors.optionWindow
            optionWindowCheckboxColor = AppColors.optionWindowCheckbox
        }
    }

    @inline(__always)
    private static func loadPng(
        named name: String,
        files: [String: URL]
    ) -> PlatformImage? {
        guard
            let url = files["\(name.lowercased()).png"],
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        return PlatformImage(data: data)
    }

    private static func loadAnyPng(
        names: [String],
        files: [String: URL]
    ) -> PlatformImage? {
        for name in names {
            if let image = loadPng(named: name, files: files) {
                return image
            }
        }

        return nil
    }

    private static func indexFiles(in dir: URL) -> [String: URL] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        var result: [String: URL] = [:]

        guard let direct = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return result
        }

        result.reserveCapacity(direct.count * 2)

        for url in direct {
            let values = try? url.resourceValues(forKeys: keys)

            if values?.isDirectory == true {
                guard let nested = try? fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }

                for file in nested {
                    let key = file.lastPathComponent.lowercased()
                    if result[key] == nil {
                        result[key] = file
                    }
                }
            } else {
                let key = url.lastPathComponent.lowercased()
                result[key] = url
            }
        }

        return result
    }

    private static func parseColor(_ hex: String?) -> Color? {
        guard var cleaned = hex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty
        else {
            return nil
        }

        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }

        guard let value = UInt32(cleaned, radix: 16) else {
            return nil
        }

        switch cleaned.count {
        case 6:
            return Color(
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0
            )

        case 8:
            return Color(
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0,
                opacity: Double((value >> 24) & 0xFF) / 255.0
            )

        default:
            return nil
        }
    }
}

// MARK: - Error

enum ThemeLoadError: LocalizedError {
    case metadataNotFound

    var errorDescription: String? {
        switch self {
        case .metadataNotFound:
            return "theme.json not found in theme directory"
        }
    }
}

