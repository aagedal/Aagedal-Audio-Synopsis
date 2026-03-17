//
//  ModelManager.swift
//  Audio Synopsis
//
//  Central model management for downloads and access
//

import Foundation
import Combine

/// Download progress information for UI display
struct DownloadProgress {
    let fractionCompleted: Double
    let totalBytesWritten: Int64
    let totalBytesExpected: Int64
    let bytesPerSecond: Double

    var isConnecting: Bool {
        totalBytesWritten == 0
    }

    var downloadedFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
    }

    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytesExpected, countStyle: .file)
    }

    var speedFormatted: String {
        Self.formatSpeed(bytesPerSecond)
    }

    static func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond > 0 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
        }
        return ""
    }

    var percentComplete: Int {
        Int(fractionCompleted * 100)
    }
}

/// Errors related to model management
enum ModelManagerError: LocalizedError {
    case downloadFailed(String)
    case directoryAccessFailed
    case modelNotFound(String)
    case insufficientSpace
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .directoryAccessFailed:
            return "Cannot access model directory"
        case .modelNotFound(let modelId):
            return "Whisper model '\(modelId)' is not downloaded. A Whisper model is required for transcription, even when using Apple Intelligence for summarization. Please download a model in Settings."
        case .insufficientSpace:
            return "Insufficient disk space"
        }
    }
}

/// Central model management
@MainActor
class ModelManager: ObservableObject {
    
    // MARK: - Published Properties

    @Published var whisperModelDirectory: URL?
    @Published var mlxModelDirectory: URL?
    @Published var ggufModelDirectory: URL?
    @Published var installedModels: Set<String> = []
    @Published var downloadProgress: [String: DownloadProgress] = [:]
    @Published var customModels: [ModelMetadata] = []
    @Published var error: Error?

    // MARK: - Properties

    let availableModels = ModelMetadata.allModels
    private let whisperBookmarkManager = SecurityBookmarkManager(bookmarkKey: "modelDirectoryBookmark")
    private let mlxBookmarkManager = SecurityBookmarkManager(bookmarkKey: "mlxModelDirectoryBookmark")
    private let fileManager = FileManager.default

    // MARK: - Initialization

    init() {
        Logger.info("ModelManager initialized", category: Logger.general)
        resolveWhisperModelDirectory()
        resolveMLXModelDirectory()
        resolveGGUFModelDirectory()
        scanInstalledModels()
    }

    // MARK: - Directory Management

    /// Resolve the Whisper model directory (user-selected or fallback)
    private func resolveWhisperModelDirectory() {
        Logger.info("Resolving Whisper model directory", category: Logger.general)

        // Try to restore bookmarked directory
        if let bookmarkedURL = whisperBookmarkManager.restoreBookmark() {
            if whisperBookmarkManager.startAccessingSecurityScopedResource(url: bookmarkedURL) {
                whisperModelDirectory = bookmarkedURL
                Logger.info("Using bookmarked Whisper model directory: \(bookmarkedURL.path)", category: Logger.general)
                return
            }
        }

        // Fall back to Application Support
        do {
            let appSupport = try AudioUtils.getRecordingsDirectory()
                .deletingLastPathComponent()
                .appendingPathComponent("Models")

            try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true, attributes: nil)
            whisperModelDirectory = appSupport
            Logger.info("Using Application Support for Whisper models: \(appSupport.path)", category: Logger.general)

        } catch {
            Logger.error("Failed to create Whisper model directory", error: error, category: Logger.general)
            self.error = error
        }
    }

    /// Resolve the MLX model directory (user-selected or default cache)
    private func resolveMLXModelDirectory() {
        Logger.info("Resolving MLX model directory", category: Logger.general)

        // Try to restore bookmarked directory
        if let bookmarkedURL = mlxBookmarkManager.restoreBookmark() {
            if mlxBookmarkManager.startAccessingSecurityScopedResource(url: bookmarkedURL) {
                mlxModelDirectory = bookmarkedURL
                Logger.info("Using bookmarked MLX model directory: \(bookmarkedURL.path)", category: Logger.general)
                return
            }
        }

        // Fall back to Application Support/MLXModels
        if let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let defaultMLXDir = appSupportDir.appendingPathComponent("MLXModels")
            try? fileManager.createDirectory(at: defaultMLXDir, withIntermediateDirectories: true, attributes: nil)
            mlxModelDirectory = defaultMLXDir
            Logger.info("Using default MLX model directory: \(defaultMLXDir.path)", category: Logger.general)
        }
    }

    /// Resolve the GGUF model directory (default Application Support)
    private func resolveGGUFModelDirectory() {
        Logger.info("Resolving GGUF model directory", category: Logger.general)

        if let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let defaultGGUFDir = appSupportDir.appendingPathComponent("GGUFModels")
            try? fileManager.createDirectory(at: defaultGGUFDir, withIntermediateDirectories: true, attributes: nil)
            ggufModelDirectory = defaultGGUFDir
            Logger.info("Using GGUF model directory: \(defaultGGUFDir.path)", category: Logger.general)
        }
    }

    /// Set a new user-selected Whisper model directory
    func setWhisperModelDirectory(_ url: URL) {
        Logger.info("Setting Whisper model directory: \(url.path)", category: Logger.general)

        guard whisperBookmarkManager.saveBookmark(for: url) else {
            Logger.error("Failed to save bookmark for Whisper directory", category: Logger.general)
            error = SecurityBookmarkError.bookmarkCreationFailed
            return
        }

        guard whisperBookmarkManager.startAccessingSecurityScopedResource(url: url) else {
            Logger.error("Failed to access Whisper directory", category: Logger.general)
            error = SecurityBookmarkError.accessDenied
            return
        }

        whisperModelDirectory = url
        scanInstalledModels()
    }

    /// Set a new user-selected MLX model directory
    func setMLXModelDirectory(_ url: URL) {
        Logger.info("Setting MLX model directory: \(url.path)", category: Logger.general)

        guard mlxBookmarkManager.saveBookmark(for: url) else {
            Logger.error("Failed to save bookmark for MLX directory", category: Logger.general)
            error = SecurityBookmarkError.bookmarkCreationFailed
            return
        }

        guard mlxBookmarkManager.startAccessingSecurityScopedResource(url: url) else {
            Logger.error("Failed to access MLX directory", category: Logger.general)
            error = SecurityBookmarkError.accessDenied
            return
        }

        mlxModelDirectory = url
    }
    
    // MARK: - Model Discovery
    
    /// Scan the model directory for installed models (known + custom ggml-*.bin files)
    func scanInstalledModels() {
        guard let directory = whisperModelDirectory else {
            Logger.warning("Cannot scan models: no directory set", category: Logger.general)
            return
        }

        Logger.debug("Scanning for installed models in: \(directory.path)", category: Logger.general)

        var found = Set<String>()
        let knownFilenames = Set(availableModels.map { $0.filename })

        // Check known models
        for model in availableModels {
            let modelPath = directory.appendingPathComponent(model.filename)
            if fileManager.fileExists(atPath: modelPath.path) {
                found.insert(model.id)
                Logger.debug("Found installed model: \(model.name)", category: Logger.general)
            }
        }

        // Discover custom ggml-*.bin files not in the known list
        var discovered: [ModelMetadata] = []
        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                guard filename.hasSuffix(".bin"), !knownFilenames.contains(filename) else { continue }

                let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
                let sizeBytes = Int64(attrs?.fileSize ?? 0)
                let displayName = filename
                    .replacingOccurrences(of: ".bin", with: "")
                    .replacingOccurrences(of: "ggml-", with: "")
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .localizedCapitalized

                let id = "custom-\(filename)"
                let model = ModelMetadata(
                    id: id,
                    name: displayName,
                    type: .whisper,
                    filename: filename,
                    downloadURL: URL(string: "file:///unused")!,
                    sizeBytes: sizeBytes,
                    description: "Custom model (\(filename))"
                )
                discovered.append(model)
                found.insert(id)
                Logger.debug("Discovered custom model: \(filename)", category: Logger.general)
            }
        }

        customModels = discovered
        installedModels = found

        // Scan GGUF model directory
        scanGGUFModels(into: &found)

        installedModels = found
        Logger.info("Found \(found.count) installed models", category: Logger.general)
    }

    /// Scan GGUF model directory for installed .gguf files
    private func scanGGUFModels(into found: inout Set<String>) {
        guard let directory = ggufModelDirectory else { return }

        Logger.debug("Scanning for GGUF models in: \(directory.path)", category: Logger.general)

        // Check known GGUF models
        for model in availableModels where model.type == .gguf {
            let modelPath = directory.appendingPathComponent(model.filename)
            if fileManager.fileExists(atPath: modelPath.path) {
                found.insert(model.id)
                Logger.debug("Found installed GGUF model: \(model.name)", category: Logger.general)
            }
        }

        // Discover custom .gguf files
        let knownGGUFFilenames = Set(availableModels.filter { $0.type == .gguf }.map { $0.filename })
        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                guard filename.hasSuffix(".gguf"), !knownGGUFFilenames.contains(filename) else { continue }

                let id = "custom-gguf-\(filename)"
                guard !found.contains(id) else { continue }
                found.insert(id)
                Logger.debug("Discovered custom GGUF model: \(filename)", category: Logger.general)
            }
        }
    }
    
    /// Get the file path for a specific model
    /// - Parameter modelId: Model identifier
    /// - Returns: URL to the model file, or nil if not installed
    func getModelPath(for modelId: String) -> URL? {
        // Check custom path models first
        if modelId.hasPrefix("custom-whisper-") {
            return getCustomWhisperModelPath(for: modelId)
        }

        guard let directory = whisperModelDirectory else {
            Logger.warning("Cannot get model path: no directory set", category: Logger.general)
            return nil
        }

        // Check known models first, then custom models
        let allModels = availableModels + customModels
        guard let model = allModels.first(where: { $0.id == modelId }) else {
            Logger.warning("Model not found in available or custom models: \(modelId)", category: Logger.general)
            return nil
        }

        let modelPath = directory.appendingPathComponent(model.filename)

        if fileManager.fileExists(atPath: modelPath.path) {
            Logger.debug("Model path for \(modelId): \(modelPath.path)", category: Logger.general)
            return modelPath
        } else {
            Logger.warning("Model file does not exist: \(modelId)", category: Logger.general)
            return nil
        }
    }

    /// Get the file path for a custom path whisper model by resolving its bookmark
    private func getCustomWhisperModelPath(for modelId: String) -> URL? {
        guard let entry = ModelSettings.customWhisperModels.first(where: { $0.id == modelId }),
              let url = entry.resolveURL() else {
            Logger.warning("Cannot resolve custom whisper model: \(modelId)", category: Logger.general)
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            Logger.warning("Cannot access custom whisper model: \(url.path)", category: Logger.general)
            return nil
        }

        if fileManager.fileExists(atPath: url.path) {
            Logger.debug("Custom whisper model path for \(modelId): \(url.path)", category: Logger.general)
            return url
        }

        url.stopAccessingSecurityScopedResource()
        Logger.warning("Custom whisper model file does not exist: \(url.path)", category: Logger.general)
        return nil
    }
    
    /// Get the file path for a GGUF model
    func getGGUFModelPath(for modelId: String) -> URL? {
        // Check custom GGUF path models (bookmark-based first, then filename-based)
        if modelId.hasPrefix("custom-gguf-") {
            // Try bookmark-based lookup (UUID IDs from file picker)
            if let entry = ModelSettings.customGGUFModels.first(where: { $0.id == modelId }),
               let url = entry.resolveURL() {
                guard url.startAccessingSecurityScopedResource() else {
                    Logger.warning("Cannot access custom GGUF model: \(url.path)", category: Logger.general)
                    return nil
                }
                if fileManager.fileExists(atPath: url.path) {
                    return url
                }
                url.stopAccessingSecurityScopedResource()
                return nil
            }

            // Fall back to filename-based lookup (discovered in GGUF directory)
            let filename = String(modelId.dropFirst("custom-gguf-".count))
            guard let directory = ggufModelDirectory else { return nil }
            let path = directory.appendingPathComponent(filename)
            return fileManager.fileExists(atPath: path.path) ? path : nil
        }

        guard let directory = ggufModelDirectory else {
            Logger.warning("Cannot get GGUF model path: no directory set", category: Logger.general)
            return nil
        }

        guard let model = availableModels.first(where: { $0.id == modelId && $0.type == .gguf }) else {
            Logger.warning("GGUF model not found: \(modelId)", category: Logger.general)
            return nil
        }

        let modelPath = directory.appendingPathComponent(model.filename)
        if fileManager.fileExists(atPath: modelPath.path) {
            return modelPath
        }
        return nil
    }

    /// Check if a model is installed
    /// - Parameter modelId: Model identifier
    /// - Returns: true if installed
    func isModelInstalled(_ modelId: String) -> Bool {
        installedModels.contains(modelId)
    }
    
    // MARK: - Model Download
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

    /// Maximum number of retry attempts when a connection times out
    private static let maxDownloadRetries = 3

    /// Download a model
    /// - Parameter metadata: Model metadata
    func downloadModel(_ metadata: ModelMetadata) async throws {
        Logger.info("Starting download for model: \(metadata.name)", category: Logger.general)

        let directory: URL?
        switch metadata.type {
        case .gguf:
            directory = ggufModelDirectory
        default:
            directory = whisperModelDirectory
        }

        guard let directory else {
            Logger.error("Cannot download: no directory set", category: Logger.general)
            throw ModelManagerError.directoryAccessFailed
        }

        let destination = directory.appendingPathComponent(metadata.filename)

        // Check if already exists
        if fileManager.fileExists(atPath: destination.path) {
            Logger.info("Model already exists: \(metadata.name)", category: Logger.general)
            _ = await MainActor.run {
                installedModels.insert(metadata.id)
            }
            return
        }

        // Mark as downloading
        await MainActor.run {
            downloadProgress[metadata.id] = DownloadProgress(fractionCompleted: 0, totalBytesWritten: 0, totalBytesExpected: metadata.sizeBytes, bytesPerSecond: 0)
        }

        // Retry loop for connection-phase stalls.
        // Wrapped in do/catch to guarantee downloadProgress cleanup on ANY failure path.
        do {
            var lastError: Error?
            for attempt in 1...Self.maxDownloadRetries {
                if attempt > 1 {
                    Logger.info("Download retry attempt \(attempt)/\(Self.maxDownloadRetries) for \(metadata.name)", category: Logger.general)
                    // Reset progress to connecting state between retries
                    await MainActor.run {
                        downloadProgress[metadata.id] = DownloadProgress(fractionCompleted: 0, totalBytesWritten: 0, totalBytesExpected: metadata.sizeBytes, bytesPerSecond: 0)
                    }
                }

                do {
                    try await attemptDownload(metadata: metadata, destination: destination)
                    return // Success
                } catch {
                    lastError = error
                    let nsError = error as NSError
                    // Don't retry if user cancelled
                    if nsError.code == NSURLErrorCancelled {
                        throw error
                    }
                    // Retry on connection timeout (URLSession's built-in timeout)
                    if nsError.code == NSURLErrorTimedOut {
                        Logger.warning("Connection timed out (attempt \(attempt)/\(Self.maxDownloadRetries))", category: Logger.general)
                        continue
                    }
                    // For other errors, don't retry
                    throw error
                }
            }

            // All retries exhausted
            Logger.error("Model download failed after \(Self.maxDownloadRetries) attempts", category: Logger.general)
            self.error = lastError
            throw ModelManagerError.downloadFailed("Download failed after \(Self.maxDownloadRetries) connection attempts. Please check your network and try again.")
        } catch {
            // Guarantee cleanup of downloadProgress on ALL failure paths
            downloadProgress.removeValue(forKey: metadata.id)
            throw error
        }
    }

    /// Single download attempt — uses delegate-only downloadTask (no completion handler)
    /// so that didWriteData fires for real-time progress updates.
    private func attemptDownload(metadata: ModelMetadata, destination: URL) async throws {
        let delegate = DownloadDelegate(expectedBytes: metadata.sizeBytes) { progress in
            Task { @MainActor [weak self] in
                self?.downloadProgress[metadata.id] = progress
            }
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30   // Fires NSURLErrorTimedOut if no data for 30s
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        Logger.info("Downloading from: \(metadata.downloadURL)", category: Logger.general)

        return try await withCheckedThrowingContinuation { continuation in
            delegate.onComplete = { [weak self] result in
                switch result {
                case .success(let tempURL):
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: destination)
                        Logger.info("Model downloaded successfully: \(metadata.name)", category: Logger.general)
                        Task { @MainActor in
                            self?.downloadTasks.removeValue(forKey: metadata.id)
                            self?.installedModels.insert(metadata.id)
                            self?.downloadProgress.removeValue(forKey: metadata.id)
                        }
                        continuation.resume()
                    } catch {
                        Logger.error("Failed to move downloaded model", error: error, category: Logger.general)
                        try? FileManager.default.removeItem(at: tempURL)
                        Task { @MainActor in
                            self?.downloadTasks.removeValue(forKey: metadata.id)
                            self?.downloadProgress.removeValue(forKey: metadata.id)
                            self?.error = error
                        }
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    Task { @MainActor in
                        self?.downloadTasks.removeValue(forKey: metadata.id)
                    }
                    continuation.resume(throwing: error)
                }
            }

            // Use delegate-only downloadTask — no completion handler — so delegate
            // methods (didWriteData, didFinishDownloadingTo, didCompleteWithError) all fire.
            let task = session.downloadTask(with: metadata.downloadURL)
            self.downloadTasks[metadata.id] = task
            task.resume()
        }
    }
    
    /// Cancel a model download
    /// - Parameter modelId: ID of the model to cancel
    func cancelDownload(for modelId: String) {
        Logger.info("Cancelling download for model: \(modelId)", category: Logger.general)
        downloadTasks[modelId]?.cancel()
        downloadTasks.removeValue(forKey: modelId)
        downloadProgress.removeValue(forKey: modelId)
    }
    
    /// Import a custom model file into the model directory
    /// - Parameter sourceURL: URL of the model file to import
    func importModel(from sourceURL: URL) throws {
        guard let directory = whisperModelDirectory else {
            throw ModelManagerError.directoryAccessFailed
        }

        let filename = sourceURL.lastPathComponent
        let destination = directory.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: destination.path) {
            Logger.info("Model file already exists in directory: \(filename)", category: Logger.general)
        } else {
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            try fileManager.copyItem(at: sourceURL, to: destination)
            Logger.info("Imported custom model: \(filename)", category: Logger.general)
        }

        scanInstalledModels()
    }

    /// Delete a downloaded model
    /// - Parameter metadata: Model metadata
    func deleteModel(_ metadata: ModelMetadata) throws {
        Logger.info("Deleting model: \(metadata.name)", category: Logger.general)

        guard let directory = whisperModelDirectory else {
            throw ModelManagerError.directoryAccessFailed
        }

        let modelPath = directory.appendingPathComponent(metadata.filename)

        if fileManager.fileExists(atPath: modelPath.path) {
            try fileManager.removeItem(at: modelPath)
            installedModels.remove(metadata.id)
            Logger.info("Model deleted successfully: \(metadata.name)", category: Logger.general)

            // Rescan to update custom models list
            if metadata.id.hasPrefix("custom-") {
                scanInstalledModels()
            }
        }
    }
    
    // MARK: - Disk Space
    
    /// Get available disk space in bytes
    var whisperAvailableDiskSpace: Int64? {
        guard let directory = whisperModelDirectory else { return nil }
        
        do {
            let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage
        } catch {
            Logger.error("Failed to get disk space", error: error, category: Logger.general)
            return nil
        }
    }
    
    nonisolated deinit {
        // Note: Can't call main actor methods in deinit
        // The bookmark resource will be released when the manager is deallocated
    }
}

// MARK: - Download Delegate

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (DownloadProgress) -> Void
    let expectedBytes: Int64

    /// Called when the download task fully completes, with either the temp file URL or an error.
    var onComplete: ((Result<URL, Error>) -> Void)?

    private var downloadedURL: URL?
    private var fileError: Error?
    private var lastReportedPercent: Int = -1
    private var lastTimestamp: CFAbsoluteTime = 0
    private var lastBytesWritten: Int64 = 0
    private var currentSpeed: Double = 0

    /// Set to true once first data bytes are received; used by connection timeout logic.
    private(set) var hasReceivedData = false

    init(expectedBytes: Int64, onProgress: @escaping (DownloadProgress) -> Void) {
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Validate HTTP response
        if let httpResponse = downloadTask.response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            fileError = ModelManagerError.downloadFailed("HTTP error: \(httpResponse.statusCode)")
            return
        }

        // The system deletes `location` after this method returns, so move to a stable temp path
        let stableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-download")
        do {
            try FileManager.default.moveItem(at: location, to: stableURL)
            downloadedURL = stableURL
        } catch {
            fileError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let error {
            onComplete?(.failure(error))
        } else if let fileError {
            onComplete?(.failure(fileError))
        } else if let url = downloadedURL {
            onComplete?(.success(url))
        } else {
            onComplete?(.failure(ModelManagerError.downloadFailed("Download completed but file was not saved")))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        hasReceivedData = true

        // Use server-reported size if available, otherwise fall back to metadata
        let totalBytes: Int64
        if totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown && totalBytesExpectedToWrite > 0 {
            totalBytes = totalBytesExpectedToWrite
        } else {
            totalBytes = expectedBytes
        }

        guard totalBytes > 0 else { return }

        let fraction = min(max(Double(totalBytesWritten) / Double(totalBytes), 0.0), 1.0)

        // Calculate speed over 0.5s intervals to avoid jitter
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastTimestamp
        if elapsed >= 0.5 {
            let bytesDelta = totalBytesWritten - lastBytesWritten
            currentSpeed = Double(bytesDelta) / elapsed
            lastTimestamp = now
            lastBytesWritten = totalBytesWritten
        }

        // Throttle: only report on whole-percent changes
        let currentPercent = Int(fraction * 100)
        guard currentPercent > lastReportedPercent else { return }
        lastReportedPercent = currentPercent

        let progress = DownloadProgress(
            fractionCompleted: fraction,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpected: totalBytes,
            bytesPerSecond: currentSpeed
        )
        onProgress(progress)
    }
}
