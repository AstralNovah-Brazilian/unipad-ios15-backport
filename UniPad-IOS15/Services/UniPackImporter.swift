import Foundation
import Compression
import os.log

protocol UniPackImporterDelegate: AnyObject, Sendable {
    @MainActor func onImportStart()
    @MainActor func onImportComplete(folder: URL)
    @MainActor func onImportError(_ error: Error)
}

actor UniPackImporter {
    enum ImportError: LocalizedError {
        case emptyZip
        case criticalError(String)
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyZip:
                return "ZIP file is empty"
            case .criticalError(let message):
                return "Critical error: \(message)"
            case .extractionFailed(let message):
                return "Extraction failed: \(message)"
            }
        }
    }

    enum ImportState: Sendable {
        case idle
        case importing
        case completed(URL)
        case failed(String)
    }

    typealias Delegate = UniPackImporterDelegate

    private let logger = Logger(
        subsystem: "com.kimjisub.unipad",
        category: "Importer"
    )

    @discardableResult
    func importPack(
        from sourceURL: URL,
        to workspace: URL,
        delegate: Delegate?
    ) async throws -> URL {
        try await importPack(
            from: sourceURL,
            fileName: sourceURL.deletingPathExtension().lastPathComponent,
            to: workspace,
            delegate: delegate
        )
    }

    @discardableResult
    func importPack(
        data: Data,
        fileName: String,
        to workspace: URL,
        delegate: Delegate?
    ) async throws -> URL {
        let fm = FileManager.default
        let tempZip = fm.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".zip"
        )
        defer { try? fm.removeItem(at: tempZip) }

        do {
            try data.write(to: tempZip, options: .atomic)
        } catch {
            logger.error(
                "Failed to write temp ZIP: \(error.localizedDescription)"
            )
            await delegate?.onImportError(error)
            throw error
        }

        return try await importPack(
            from: tempZip,
            fileName: URL(fileURLWithPath: fileName)
                .deletingPathExtension()
                .lastPathComponent,
            to: workspace,
            delegate: delegate
        )
    }

    func extractOnly(at zipURL: URL, to destination: URL) throws {
        try extractZip(at: zipURL, to: destination)
    }

    // MARK: - Import Core

    @discardableResult
    private func importPack(
        from sourceURL: URL,
        fileName: String,
        to workspace: URL,
        delegate: Delegate?
    ) async throws -> URL {
        let fm = FileManager.default
        let safeName = FileManagerExtensions.filterFilename(fileName)
        let finalName = safeName.isEmpty ? "UniPack" : safeName
        let targetFolder = FileManagerExtensions.makeNextPath(
            dir: workspace,
            name: finalName,
            extension: ""
        )

        await delegate?.onImportStart()

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fm.createDirectory(
                at: targetFolder,
                withIntermediateDirectories: true
            )

            let tempZip = fm.temporaryDirectory.appendingPathComponent(
                UUID().uuidString + ".zip"
            )
            defer { try? fm.removeItem(at: tempZip) }

            try fm.copyItem(at: sourceURL, to: tempZip)
            try extractZip(at: tempZip, to: targetFolder)
            FileManagerExtensions.removeDoubleFolder(at: targetFolder)

            let unipack = UniPackFolder(rootFolder: targetFolder)
            unipack.load()
            unipack.loadDetail()

            if unipack.criticalError {
                throw ImportError.criticalError(
                    unipack.errorDetail ?? "Invalid unipack structure"
                )
            }

            await delegate?.onImportComplete(folder: targetFolder)
            logger.info(
                "Import completed: \(targetFolder.lastPathComponent)"
            )
            return targetFolder
        } catch {
            FileManagerExtensions.deleteDirectory(at: targetFolder)
            logger.error(
                "Import failed: \(error.localizedDescription)"
            )
            await delegate?.onImportError(error)
            throw error
        }
    }

    // MARK: - ZIP Extraction

    private func extractZip(at zipURL: URL, to destination: URL) throws {
        try FileManager.default.unzipItem(
            at: zipURL,
            to: destination
        )
    }
}

// MARK: - FileManager ZIP Extension

extension FileManager {
    func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        let data = try Data(
            contentsOf: sourceURL,
            options: .mappedIfSafe
        )

        guard !data.isEmpty else {
            throw UniPackImporter.ImportError.emptyZip
        }

        func readUInt16LE(at offset: Int) -> UInt16? {
            guard offset >= 0, offset + 2 <= data.count else { return nil }
            return UInt16(data[offset]) |
                (UInt16(data[offset + 1]) << 8)
        }

        func readUInt32LE(at offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= data.count else { return nil }
            return UInt32(data[offset]) |
                (UInt32(data[offset + 1]) << 8) |
                (UInt32(data[offset + 2]) << 16) |
                (UInt32(data[offset + 3]) << 24)
        }

        let maxEOCDSearch = min(data.count, 66_000)
        let eocdStart = data.count - maxEOCDSearch
        var eocdOffset: Int?

        if data.count >= 22 {
            var offset = data.count - 22
            while offset >= eocdStart {
                if readUInt32LE(at: offset) == 0x0605_4B50 {
                    eocdOffset = offset
                    break
                }
                offset -= 1
            }
        }

        guard let eocdOffset = eocdOffset else {
            throw UniPackImporter.ImportError.extractionFailed(
                "EOCD not found"
            )
        }

        guard
            let totalEntriesU16 = readUInt16LE(at: eocdOffset + 10),
            let centralDirSizeU32 = readUInt32LE(at: eocdOffset + 12),
            let centralDirOffsetU32 = readUInt32LE(at: eocdOffset + 16)
        else {
            throw UniPackImporter.ImportError.extractionFailed(
                "Invalid EOCD"
            )
        }

        let totalEntries = Int(totalEntriesU16)
        let centralDirSize = Int(centralDirSizeU32)
        let centralDirOffset = Int(centralDirOffsetU32)

        guard
            centralDirOffset >= 0,
            centralDirSize >= 0,
            centralDirOffset <= data.count,
            centralDirSize <= data.count - centralDirOffset
        else {
            throw UniPackImporter.ImportError.extractionFailed(
                "Invalid central directory range"
            )
        }

        struct Entry {
            let fileName: String
            let compressionMethod: UInt16
            let compressedSize: Int
            let uncompressedSize: Int
            let localHeaderOffset: Int
        }

        var entries: [Entry] = []
        entries.reserveCapacity(totalEntries)
        var cursor = centralDirOffset

        for _ in 0..<totalEntries {
            guard
                cursor + 46 <= data.count,
                readUInt32LE(at: cursor) == 0x0201_4B50
            else {
                throw UniPackImporter.ImportError.extractionFailed(
                    "Corrupted central directory"
                )
            }

            guard
                let generalPurposeFlags = readUInt16LE(at: cursor + 8),
                let compressionMethod = readUInt16LE(at: cursor + 10),
                let compressedSizeU32 = readUInt32LE(at: cursor + 20),
                let uncompressedSizeU32 = readUInt32LE(at: cursor + 24),
                let fileNameLengthU16 = readUInt16LE(at: cursor + 28),
                let extraLengthU16 = readUInt16LE(at: cursor + 30),
                let commentLengthU16 = readUInt16LE(at: cursor + 32),
                let localHeaderOffsetU32 = readUInt32LE(at: cursor + 42)
            else {
                throw UniPackImporter.ImportError.extractionFailed(
                    "Corrupted central directory entry"
                )
            }

            let fileNameLength = Int(fileNameLengthU16)
            let extraLength = Int(extraLengthU16)
            let commentLength = Int(commentLengthU16)
            let localHeaderOffset = Int(localHeaderOffsetU32)
            let fileNameStart = cursor + 46
            let fileNameEnd = fileNameStart + fileNameLength
            let nextCursor = fileNameEnd + extraLength + commentLength

            guard
                fileNameEnd <= data.count,
                nextCursor <= data.count
            else {
                throw UniPackImporter.ImportError.extractionFailed(
                    "Invalid entry range"
                )
            }

            let rawName = data[fileNameStart..<fileNameEnd]
            let fileName = Self.decodeEntryName(
                rawName,
                utf8Flag: generalPurposeFlags & 0x0800 != 0
            )

            if !fileName.isEmpty {
                entries.append(
                    Entry(
                        fileName: fileName,
                        compressionMethod: compressionMethod,
                        compressedSize: Int(compressedSizeU32),
                        uncompressedSize: Int(uncompressedSizeU32),
                        localHeaderOffset: localHeaderOffset
                    )
                )
            }

            cursor = nextCursor
        }

        let root = destinationURL.standardizedFileURL
        let rootPath = root.path.hasSuffix("/")
            ? root.path
            : root.path + "/"

        for entry in entries {
            let normalizedName = entry.fileName.replacingOccurrences(
                of: "\\",
                with: "/"
            )
            guard
                !normalizedName.hasPrefix("/"),
                !normalizedName.hasPrefix("~")
            else {
                continue
            }

            let entryPath = root
                .appendingPathComponent(normalizedName)
                .standardizedFileURL
            let entryPathString = entryPath.path

            guard
                entryPathString == root.path ||
                entryPathString.hasPrefix(rootPath)
            else {
                continue
            }

            if normalizedName.hasSuffix("/") {
                try createDirectory(
                    at: entryPath,
                    withIntermediateDirectories: true
                )
                continue
            }

            let localHeader = entry.localHeaderOffset
            guard
                localHeader >= 0,
                localHeader + 30 <= data.count,
                readUInt32LE(at: localHeader) == 0x0403_4B50
            else {
                throw UniPackImporter.ImportError.extractionFailed(
                    "Invalid local header for \(entry.fileName)"
                )
            }

            guard
                let localNameLength = readUInt16LE(at: localHeader + 26),
                let localExtraLength = readUInt16LE(at: localHeader + 28)
            else {
                throw UniPackImporter.ImportError.extractionFailed(
                    "Invalid local header lengths for \(entry.fileName)"
                )
            }

            let dataStart =
                localHeader +
                30 +
                Int(localNameLength) +
                Int(localExtraLength)

            guard
                dataStart >= 0,
                entry.compressedSize >= 0,
                dataStart <= data.count,
                entry.compressedSize <= data.count - dataStart
            else {
                throw UniPackImporter.ImportError.extractionFailed(
                    "Compressed data out of bounds for \(entry.fileName)"
                )
            }

            let dataEnd = dataStart + entry.compressedSize
            let parentDir = entryPath.deletingLastPathComponent()

            if !fileExists(atPath: parentDir.path) {
                try createDirectory(
                    at: parentDir,
                    withIntermediateDirectories: true
                )
            }

            let compressedData = data[dataStart..<dataEnd]

            switch entry.compressionMethod {
            case 0:
                try Data(compressedData).write(
                    to: entryPath,
                    options: .atomic
                )

            case 8:
                let decompressed = try Self.decompressDeflate(
                    Data(compressedData),
                    expectedSize: entry.uncompressedSize
                )
                try decompressed.write(
                    to: entryPath,
                    options: .atomic
                )

            default:
                throw UniPackImporter.ImportError.extractionFailed(
                    "Unsupported compression method \(entry.compressionMethod) for \(entry.fileName)"
                )
            }
        }
    }

    private static func decodeEntryName(
        _ raw: Data.SubSequence,
        utf8Flag: Bool
    ) -> String {
        let data = Data(raw)

        if utf8Flag, let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        let cp949 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(0x0422)
        )
        if let korean = String(data: data, encoding: cp949) {
            return korean
        }

        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    private static func decompressDeflate(
        _ compressedData: Data,
        expectedSize: Int
    ) throws -> Data {
        if expectedSize == 0 || compressedData.isEmpty {
            return Data()
        }

        let maxBufferSize = 512 * 1024 * 1024
        guard
            expectedSize >= 0,
            expectedSize <= maxBufferSize
        else {
            throw UniPackImporter.ImportError.extractionFailed(
                "Entry too large (\(expectedSize) bytes)"
            )
        }

        var bufferSize = max(expectedSize, 65_536)

        while bufferSize <= maxBufferSize {
            let destination = UnsafeMutablePointer<UInt8>.allocate(
                capacity: bufferSize
            )
            defer { destination.deallocate() }

            let decompressedSize = compressedData.withUnsafeBytes {
                source -> Int in
                guard let base = source.baseAddress?
                    .assumingMemoryBound(to: UInt8.self)
                else {
                    return 0
                }

                return compression_decode_buffer(
                    destination,
                    bufferSize,
                    base,
                    compressedData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }

            guard decompressedSize > 0 else {
                throw UniPackImporter.ImportError.extractionFailed(
                    "Decompression failed"
                )
            }

            if decompressedSize < bufferSize {
                return Data(
                    bytes: destination,
                    count: decompressedSize
                )
            }

            if bufferSize > maxBufferSize / 2 {
                break
            }
            bufferSize *= 2
        }

        throw UniPackImporter.ImportError.extractionFailed(
            "Decompressed entry exceeds \(maxBufferSize) bytes"
        )
    }
}
