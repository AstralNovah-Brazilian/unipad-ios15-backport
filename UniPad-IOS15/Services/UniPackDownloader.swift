import Foundation
import os.log

protocol UniPackDownloaderDelegate: AnyObject, Sendable {
    @MainActor func onInstallStart()
    @MainActor func onGetFileSize(
        fileSize: Int64,
        contentLength: Int64,
        preKnownFileSize: Int64
    )
    @MainActor func onDownloadProgress(
        percent: Int,
        downloadedSize: Int64,
        fileSize: Int64
    )
    @MainActor func onImportStart()
    @MainActor func onInstallComplete(folder: URL)
    @MainActor func onError(_ error: Error)
}

actor UniPackDownloader {
    typealias Delegate = UniPackDownloaderDelegate

    enum DownloadError: LocalizedError {
        case emptyResponse
        case criticalError(String)
        case cancelled
        case httpError(statusCode: Int)
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "Empty response body"
            case .criticalError(let message):
                return "Critical error: \(message)"
            case .cancelled:
                return "Download cancelled"
            case .httpError(let statusCode):
                return "Server returned HTTP \(statusCode)"
            case .writeFailed:
                return "Could not write the downloaded file"
            }
        }
    }

    private let logger = Logger(
        subsystem: "com.kimjisub.unipad",
        category: "Downloader"
    )
    private let importer = UniPackImporter()

    func download(
        title: String,
        url: String,
        workspace: URL,
        folderName: String,
        preKnownFileSize: Int64 = 0,
        delegate: Delegate?
    ) async {
        let zipFile = FileManagerExtensions.makeNextPath(
            dir: workspace,
            name: folderName,
            extension: ".zip"
        )
        let folder = FileManagerExtensions.makeNextPath(
            dir: workspace,
            name: folderName,
            extension: ""
        )

        await delegate?.onInstallStart()

        do {
            try Task.checkCancellation()

            guard let requestURL = URL(string: url) else {
                throw DownloadError.emptyResponse
            }

            let response = try await downloadWithProgress(
                from: requestURL,
                to: zipFile,
                preKnownFileSize: preKnownFileSize,
                delegate: delegate
            )

            let contentLength = max(response.expectedContentLength, 0)
            let fileSize = max(contentLength, preKnownFileSize)

            await delegate?.onGetFileSize(
                fileSize: fileSize,
                contentLength: contentLength,
                preKnownFileSize: preKnownFileSize
            )

            try Task.checkCancellation()
            await delegate?.onImportStart()

            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )

            try await importer.extractOnly(
                at: zipFile,
                to: folder
            )
            FileManagerExtensions.removeDoubleFolder(at: folder)

            let unipack = UniPackFolder(rootFolder: folder)
            unipack.load()
            unipack.loadDetail()

            if unipack.criticalError {
                throw DownloadError.criticalError(
                    unipack.errorDetail ?? "Invalid unipack structure"
                )
            }

            try Task.checkCancellation()

            await delegate?.onInstallComplete(folder: folder)
            logger.info(
                "Download + install complete: \(folder.lastPathComponent)"
            )
        } catch is CancellationError {
            FileManagerExtensions.deleteDirectory(at: folder)
            await delegate?.onError(DownloadError.cancelled)
        } catch {
            logger.error(
                "Download failed: \(error.localizedDescription)"
            )
            FileManagerExtensions.deleteDirectory(at: folder)
            await delegate?.onError(error)
        }

        FileManagerExtensions.deleteDirectory(at: zipFile)
    }

    // MARK: - Download

    private func downloadWithProgress(
        from url: URL,
        to destination: URL,
        preKnownFileSize: Int64,
        delegate: Delegate?
    ) async throws -> URLResponse {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw DownloadError.httpError(
                statusCode: http.statusCode
            )
        }

        let contentLength = max(response.expectedContentLength, 0)
        let fileSize = max(contentLength, preKnownFileSize)

        guard let stream = OutputStream(
            url: destination,
            append: false
        ) else {
            throw DownloadError.writeFailed
        }

        stream.open()
        defer { stream.close() }

        let bufferSize = 32 * 1024
        var buffer: [UInt8] = []
        buffer.reserveCapacity(bufferSize)

        var downloadedSize: Int64 = 0
        var previousPercent = -1

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)

            if buffer.count >= bufferSize {
                try Self.writeAll(buffer, to: stream)
                downloadedSize += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                await reportProgress(
                    downloadedSize: downloadedSize,
                    fileSize: fileSize,
                    previousPercent: &previousPercent,
                    delegate: delegate
                )
            }
        }

        if !buffer.isEmpty {
            try Self.writeAll(buffer, to: stream)
            downloadedSize += Int64(buffer.count)
        }

        guard downloadedSize > 0 else {
            throw DownloadError.emptyResponse
        }

        await reportProgress(
            downloadedSize: downloadedSize,
            fileSize: fileSize,
            previousPercent: &previousPercent,
            delegate: delegate,
            forceFinal: true
        )

        return response
    }

    private func reportProgress(
        downloadedSize: Int64,
        fileSize: Int64,
        previousPercent: inout Int,
        delegate: Delegate?,
        forceFinal: Bool = false
    ) async {
        guard fileSize > 0 else { return }

        let calculated = Int(
            Double(downloadedSize) / Double(fileSize) * 100
        )
        let percent = forceFinal
            ? 100
            : min(max(calculated, 0), 100)

        guard percent != previousPercent else { return }
        previousPercent = percent

        await delegate?.onDownloadProgress(
            percent: percent,
            downloadedSize: downloadedSize,
            fileSize: fileSize
        )
    }

    private static func writeAll(
        _ bytes: [UInt8],
        to stream: OutputStream
    ) throws {
        try bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }

            var offset = 0
            while offset < buffer.count {
                let written = stream.write(
                    base.advanced(by: offset),
                    maxLength: buffer.count - offset
                )

                guard written > 0 else {
                    throw stream.streamError
                        ?? DownloadError.writeFailed
                }

                offset += written
            }
        }
    }
}
