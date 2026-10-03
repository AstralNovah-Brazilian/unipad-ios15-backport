import Foundation
import os.log

enum FileManagerExtensions {
    private static let logger = Logger(
        subsystem: "com.kimjisub.unipad",
        category: "FileManager"
    )
    private static let bytesPerMB = 1024.0 * 1024.0
    private static let filenameFilterRegex = try! NSRegularExpression(
        pattern: #"[|\\?*<":>/]+"#
    )

    static func removeDoubleFolder(at path: URL) {
        let fm = FileManager.default
        var current = path

        while true {
            guard let contents = try? fm.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            let visible = contents.filter {
                $0.lastPathComponent != "__MACOSX"
            }

            guard
                visible.count == 1,
                let single = visible.first,
                let values = try? single.resourceValues(
                    forKeys: [.isDirectoryKey]
                ),
                values.isDirectory == true
            else {
                break
            }

            moveDirectory(from: single, to: current)
            current = path
        }
    }

    static func makeNextPath(
        dir: URL,
        name: String,
        extension ext: String
    ) -> URL {
        let filtered = filterFilename(name)
        var index = 1

        while true {
            let fileName = index == 1
                ? filtered + ext
                : "\(filtered) (\(index))\(ext)"
            let candidate = dir.appendingPathComponent(fileName)

            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }

            index += 1
        }
    }

    static func filterFilename(_ original: String) -> String {
        let range = NSRange(original.startIndex..., in: original)
        return filenameFilterRegex.stringByReplacingMatches(
            in: original,
            range: range,
            withTemplate: ""
        )
    }

    static func moveDirectory(from source: URL, to target: URL) {
        let fm = FileManager.default
        let sourcePath = source.standardizedFileURL.path
        guard sourcePath != target.standardizedFileURL.path else { return }

        do {
            let sourceContents = try fm.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var deferred: [(parked: URL, dest: URL)] = []

            for item in sourceContents {
                let dest = target.appendingPathComponent(
                    item.lastPathComponent
                )

                if dest.standardizedFileURL.path == sourcePath {
                    let parked = target.appendingPathComponent(
                        ".unipad-move-\(UUID().uuidString)"
                    )
                    try fm.moveItem(at: item, to: parked)
                    deferred.append((parked, dest))
                    continue
                }

                let itemValues = try? item.resourceValues(
                    forKeys: [.isDirectoryKey]
                )
                let itemIsDir = itemValues?.isDirectory == true

                var destIsDir: ObjCBool = false
                let destExists = fm.fileExists(
                    atPath: dest.path,
                    isDirectory: &destIsDir
                )

                if destExists && destIsDir.boolValue && itemIsDir {
                    moveDirectory(from: item, to: dest)
                    continue
                }

                if destExists {
                    try fm.removeItem(at: dest)
                }

                try fm.moveItem(at: item, to: dest)
            }

            try fm.removeItem(at: source)

            for entry in deferred {
                try fm.moveItem(
                    at: entry.parked,
                    to: entry.dest
                )
            }
        } catch {
            logger.error(
                "moveDirectory failed: \(error.localizedDescription)"
            )
        }
    }

    static func deleteDirectory(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func copyDirectory(from source: URL, to target: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        if fm.fileExists(
            atPath: source.path,
            isDirectory: &isDir
        ), isDir.boolValue {
            try fm.createDirectory(
                at: target,
                withIntermediateDirectories: true
            )

            let contents = try fm.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for item in contents {
                try copyDirectory(
                    from: item,
                    to: target.appendingPathComponent(
                        item.lastPathComponent
                    )
                )
            }
        } else {
            try fm.copyItem(at: source, to: target)
        }
    }

    static func ensureDirectoryExists(at url: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }

        do {
            try fm.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error(
                "Failed to create directory: \(error.localizedDescription)"
            )
        }
    }

    static func byteToMB(
        _ bytes: Int64,
        format: String = "%.2f"
    ) -> String {
        String(
            format: format,
            Double(bytes) / bytesPerMB
        )
    }

    static func getFolderSize(at url: URL) async -> Int64 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(
                    returning: calculateFolderSize(at: url)
                )
            }
        }
    }

    private static func calculateFolderSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(
            atPath: url.path,
            isDirectory: &isDir
        ) else {
            return 0
        }

        if !isDir.boolValue {
            if let values = try? url.resourceValues(
                forKeys: [.fileSizeKey]
            ) {
                return Int64(values.fileSize ?? 0)
            }

            return 0
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .fileAllocatedSizeKey,
                    .fileSizeKey
                ]
            ), values.isRegularFile == true else {
                continue
            }

            total += Int64(
                values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
            )
        }

        return total
    }

    static func getInnerFileLastModified(at url: URL) -> Date {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return .distantPast
        }

        for item in contents {
            guard
                let values = try? item.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .contentModificationDateKey
                    ]
                ),
                values.isDirectory != true
            else {
                continue
            }

            return values.contentModificationDate ?? .distantPast
        }

        return .distantPast
    }

    static func sortByTime(_ urls: [URL]) -> [URL] {
        let dates = Dictionary(
            uniqueKeysWithValues: urls.map {
                ($0, getInnerFileLastModified(at: $0))
            }
        )

        return urls.sorted {
            (dates[$0] ?? .distantPast) >
            (dates[$1] ?? .distantPast)
        }
    }
}
