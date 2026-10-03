import Foundation
import Compression

enum ZipHelper {
    enum ZipError: LocalizedError {
        case compressionFailed(String)
        case directoryNotFound(String)

        var errorDescription: String? {
            switch self {
            case .compressionFailed(let message):
                return "Compression failed: \(message)"
            case .directoryNotFound(let path):
                return "Directory not found: \(path)"
            }
        }
    }

    private struct Entry {
        let name: String
        let localHeaderOffset: Int
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let method: UInt16
    }

    private static let crc32Table: [UInt32] = {
        (0..<256).map { value in
            var crc = UInt32(value)
            for _ in 0..<8 {
                crc = (crc & 1) != 0
                    ? (crc >> 1) ^ 0xEDB88320
                    : crc >> 1
            }
            return crc
        }
    }()

    static func zipDirectory(source: URL, destination: URL) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ZipError.directoryNotFound(source.path)
        }

        var zipData = Data()
        zipData.reserveCapacity(64 * 1024)
        var entries: [Entry] = []

        guard let enumerator = fm.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ZipError.compressionFailed("Unable to enumerate source directory")
        }

        let basePath = source.standardizedFileURL.path
        for case let fileURL as URL in enumerator {
            let path = fileURL.standardizedFileURL.path
            guard path.count > basePath.count else { continue }

            var relativePath = String(path.dropFirst(basePath.count))
            if relativePath.hasPrefix("/") {
                relativePath.removeFirst()
            }
            guard !relativePath.isEmpty else { continue }

            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = values.isDirectory == true
            let entryName = isDirectory ? relativePath + "/" : relativePath
            let nameData = Data(entryName.utf8)
            let localHeaderOffset = zipData.count

            if isDirectory {
                writeLocalFileHeader(
                    to: &zipData,
                    nameData: nameData,
                    crc32: 0,
                    compressedSize: 0,
                    uncompressedSize: 0
                )
                entries.append(
                    Entry(
                        name: entryName,
                        localHeaderOffset: localHeaderOffset,
                        crc32: 0,
                        compressedSize: 0,
                        uncompressedSize: 0,
                        method: 0
                    )
                )
                continue
            }

            let fileData = try Data(
                contentsOf: fileURL,
                options: .mappedIfSafe
            )
            let crc = crc32Checksum(fileData)
            let compressed = compressDeflate(fileData)
            let useDeflate = compressed.map { $0.count < fileData.count } ?? false
            let payload = useDeflate ? compressed! : fileData
            let method: UInt16 = useDeflate ? 8 : 0

            writeLocalFileHeader(
                to: &zipData,
                nameData: nameData,
                crc32: crc,
                compressedSize: payload.count,
                uncompressedSize: fileData.count,
                method: method
            )
            zipData.append(payload)

            entries.append(
                Entry(
                    name: entryName,
                    localHeaderOffset: localHeaderOffset,
                    crc32: crc,
                    compressedSize: payload.count,
                    uncompressedSize: fileData.count,
                    method: method
                )
            )
        }

        guard entries.count <= Int(UInt16.max) else {
            throw ZipError.compressionFailed("ZIP64 is not supported")
        }

        let centralDirOffset = zipData.count
        for entry in entries {
            writeCentralDirectoryEntry(
                to: &zipData,
                nameData: Data(entry.name.utf8),
                crc32: entry.crc32,
                compressedSize: entry.compressedSize,
                uncompressedSize: entry.uncompressedSize,
                localHeaderOffset: entry.localHeaderOffset,
                method: entry.method
            )
        }

        let centralDirSize = zipData.count - centralDirOffset
        guard centralDirOffset <= Int(UInt32.max),
              centralDirSize <= Int(UInt32.max) else {
            throw ZipError.compressionFailed("ZIP64 is not supported")
        }

        writeEndOfCentralDirectory(
            to: &zipData,
            entryCount: entries.count,
            centralDirSize: centralDirSize,
            centralDirOffset: centralDirOffset
        )

        try zipData.write(to: destination, options: .atomic)
    }

    // MARK: - ZIP Writers

    private static func writeLocalFileHeader(
        to data: inout Data,
        nameData: Data,
        crc32: UInt32,
        compressedSize: Int,
        uncompressedSize: Int,
        method: UInt16 = 0
    ) {
        appendUInt32(&data, 0x04034B50)
        appendUInt16(&data, 20)
        appendUInt16(&data, 0)
        appendUInt16(&data, method)
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt32(&data, crc32)
        appendUInt32(&data, UInt32(compressedSize))
        appendUInt32(&data, UInt32(uncompressedSize))
        appendUInt16(&data, UInt16(nameData.count))
        appendUInt16(&data, 0)
        data.append(nameData)
    }

    private static func writeCentralDirectoryEntry(
        to data: inout Data,
        nameData: Data,
        crc32: UInt32,
        compressedSize: Int,
        uncompressedSize: Int,
        localHeaderOffset: Int,
        method: UInt16
    ) {
        appendUInt32(&data, 0x02014B50)
        appendUInt16(&data, 20)
        appendUInt16(&data, 20)
        appendUInt16(&data, 0)
        appendUInt16(&data, method)
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt32(&data, crc32)
        appendUInt32(&data, UInt32(compressedSize))
        appendUInt32(&data, UInt32(uncompressedSize))
        appendUInt16(&data, UInt16(nameData.count))
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt32(&data, 0)
        appendUInt32(&data, UInt32(localHeaderOffset))
        data.append(nameData)
    }

    private static func writeEndOfCentralDirectory(
        to data: inout Data,
        entryCount: Int,
        centralDirSize: Int,
        centralDirOffset: Int
    ) {
        appendUInt32(&data, 0x06054B50)
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt16(&data, UInt16(entryCount))
        appendUInt16(&data, UInt16(entryCount))
        appendUInt32(&data, UInt32(centralDirSize))
        appendUInt32(&data, UInt32(centralDirOffset))
        appendUInt16(&data, 0)
    }

    // MARK: - Helpers

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func compressDeflate(_ input: Data) -> Data? {
        guard !input.isEmpty else { return Data() }

        let capacity = max(input.count, 64)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }

        let compressedSize = input.withUnsafeBytes { source -> Int in
            guard let base = source.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_encode_buffer(
                destination,
                capacity,
                base,
                input.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else { return nil }
        return Data(bytes: destination, count: compressedSize)
    }

    private static func crc32Checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for index in 0..<buffer.count {
                crc = crc32Table[Int((crc ^ UInt32(bytes[index])) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}
