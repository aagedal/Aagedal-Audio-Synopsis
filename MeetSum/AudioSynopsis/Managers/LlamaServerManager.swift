//
//  LlamaServerManager.swift
//  Audio Synopsis
//
//  Manages the llama-server subprocess lifecycle and HTTP API
//

import Foundation
import Combine
import AppKit
import zlib

/// Manages a bundled llama-server process for GGUF model inference
@MainActor
class LlamaServerManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isRunning = false
    @Published var isLoading = false
    @Published var loadedModelPath: URL?
    @Published var error: Error?
    @Published var isDownloadingBinary = false
    @Published var binaryDownloadProgress: DownloadProgress?

    // MARK: - Constants

    /// Pinned llama.cpp release version
    static let llamaCppVersion = "b8391"
    private static let downloadURL = URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/\(llamaCppVersion)/llama-\(llamaCppVersion)-bin-macos-arm64.tar.gz")!
    /// Approximate download size for progress estimation
    private static let downloadSizeBytes: Int64 = 38_000_000

    // MARK: - Private Properties

    private var serverProcess: Process?
    private var serverPort: Int = 8081
    private let portRange = 8081...8089
    private var downloadTask: URLSessionDownloadTask?

    // MARK: - Initialization

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Can't await in notification handler, so use sync stop
            Task { @MainActor [weak self] in
                self?.stopServer()
            }
        }
    }

    // MARK: - Binary Management

    /// Directory where the downloaded llama-server binary and dylibs are stored
    private var llamaServerDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("LlamaServer")
    }

    /// Check if llama-server binary is available (bundled or downloaded)
    var isBinaryAvailable: Bool {
        findLlamaServerBinary() != nil
    }

    /// Ensure the llama-server binary is available, downloading if necessary
    func ensureBinaryAvailable() async throws {
        if findLlamaServerBinary() != nil {
            return
        }
        try await downloadLlamaServer()
    }

    /// Maximum number of retry attempts when a connection times out
    private static let maxDownloadRetries = 3

    /// Download llama-server from GitHub releases
    func downloadLlamaServer() async throws {
        guard let installDir = llamaServerDirectory else {
            throw LlamaServerError.downloadFailed("Cannot determine Application Support directory")
        }

        isDownloadingBinary = true
        error = nil
        binaryDownloadProgress = DownloadProgress(
            fractionCompleted: 0,
            totalBytesWritten: 0,
            totalBytesExpected: Self.downloadSizeBytes,
            bytesPerSecond: 0
        )

        Logger.info("Downloading llama-server \(Self.llamaCppVersion) from GitHub", category: Logger.processing)

        // Retry loop for connection timeouts
        var lastError: Error?
        for attempt in 1...Self.maxDownloadRetries {
            if attempt > 1 {
                Logger.info("llama-server download retry attempt \(attempt)/\(Self.maxDownloadRetries)", category: Logger.processing)
                binaryDownloadProgress = DownloadProgress(fractionCompleted: 0, totalBytesWritten: 0, totalBytesExpected: Self.downloadSizeBytes, bytesPerSecond: 0)
            }

            do {
                let tarballURL = try await attemptBinaryDownload()

                // Extract the tarball
                try await extractLlamaServer(tarball: tarballURL, to: installDir)

                // Clean up tarball
                try? FileManager.default.removeItem(at: tarballURL)

                isDownloadingBinary = false
                binaryDownloadProgress = nil
                downloadTask = nil

                Logger.info("llama-server downloaded and installed to \(installDir.path)", category: Logger.processing)
                return // Success
            } catch {
                lastError = error
                let nsError = error as NSError
                // Don't retry if user cancelled
                if nsError.code == NSURLErrorCancelled {
                    isDownloadingBinary = false
                    binaryDownloadProgress = nil
                    downloadTask = nil
                    throw error
                }
                // Retry on connection timeout
                if nsError.code == NSURLErrorTimedOut {
                    Logger.warning("llama-server connection timed out (attempt \(attempt)/\(Self.maxDownloadRetries))", category: Logger.processing)
                    continue
                }
                // For other errors, don't retry
                isDownloadingBinary = false
                binaryDownloadProgress = nil
                downloadTask = nil
                self.error = error
                Logger.error("Failed to download llama-server", error: error, category: Logger.processing)
                throw error
            }
        }

        // All retries exhausted
        isDownloadingBinary = false
        binaryDownloadProgress = nil
        downloadTask = nil
        self.error = lastError
        Logger.error("Failed to download llama-server after \(Self.maxDownloadRetries) attempts", category: Logger.processing)
        throw LlamaServerError.downloadFailed("Download failed after \(Self.maxDownloadRetries) connection attempts. Please check your network and try again.")
    }

    /// Single download attempt — uses delegate-only downloadTask (no completion handler)
    /// so that didWriteData fires for real-time progress updates.
    private func attemptBinaryDownload() async throws -> URL {
        let delegate = DownloadDelegate(expectedBytes: Self.downloadSizeBytes) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.binaryDownloadProgress = progress
            }
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30   // Fires NSURLErrorTimedOut if no data for 30s
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let tarballURL: URL = try await withCheckedThrowingContinuation { continuation in
            delegate.onComplete = { result in
                switch result {
                case .success(let tempURL):
                    // Rename to .tar.gz so extraction recognizes the format
                    let stableTempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("llama-server-\(UUID().uuidString).tar.gz")
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: stableTempURL)
                        continuation.resume(returning: stableTempURL)
                    } catch {
                        try? FileManager.default.removeItem(at: tempURL)
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            // Use delegate-only downloadTask — no completion handler — so delegate
            // methods (didWriteData, didFinishDownloadingTo, didCompleteWithError) all fire.
            let task = session.downloadTask(with: Self.downloadURL)
            self.downloadTask = task
            task.resume()
        }
        return tarballURL
    }

    /// Extract llama-server binary and required dylibs from the release tarball.
    /// Uses pure Swift gzip+tar parsing to work correctly inside the app sandbox
    /// (spawning /usr/bin/tar via Process is unreliable in sandboxed apps).
    private func extractLlamaServer(tarball: URL, to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let prefix = "llama-\(Self.llamaCppVersion)/"

        // Read and decompress the .tar.gz file
        let compressedData = try Data(contentsOf: tarball)
        let tarData = try Self.decompressGzip(compressedData)

        Logger.info("Decompressed tarball: \(compressedData.count) -> \(tarData.count) bytes", category: Logger.processing)

        // Parse tar and extract files we need (server binary + dylibs)
        var extractedCount = 0
        var offset = 0

        while offset + 512 <= tarData.count {
            // Read 512-byte tar header
            let headerData = tarData[offset..<(offset + 512)]

            // Check for end-of-archive (two consecutive zero blocks)
            if headerData.allSatisfy({ $0 == 0 }) { break }

            // Parse filename (first 100 bytes, null-terminated)
            let nameBytes = headerData[offset..<(offset + 100)]
            let name = String(bytes: nameBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""

            // Parse file size (octal string at offset 124, 12 bytes)
            let sizeBytes = headerData[(offset + 124)..<(offset + 136)]
            let sizeString = String(bytes: sizeBytes.prefix(while: { $0 != 0 && $0 != 0x20 }), encoding: .utf8) ?? "0"
            let fileSize = Int(sizeString, radix: 8) ?? 0

            // Parse type flag (byte at offset 156): '0' or '\0' = regular file, '2' = symlink, '5' = directory
            let typeFlag = headerData[offset + 156]

            // Parse link target for symlinks (100 bytes at offset 157)
            let linkBytes = headerData[(offset + 157)..<(offset + 257)]
            let linkTarget = String(bytes: linkBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""

            // Parse USTAR extended name prefix (bytes 345-500)
            let prefixBytes = headerData[(offset + 345)..<(offset + 500)]
            let namePrefix = String(bytes: prefixBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            let fullName = namePrefix.isEmpty ? name : "\(namePrefix)/\(name)"

            offset += 512 // Move past header

            // Check if this file is under our target prefix
            guard fullName.hasPrefix(prefix) else {
                // Skip file data (rounded up to 512-byte blocks)
                offset += ((fileSize + 511) / 512) * 512
                continue
            }

            let localName = String(fullName.dropFirst(prefix.count))
            guard !localName.isEmpty else {
                // Skip the directory entry itself
                offset += ((fileSize + 511) / 512) * 512
                continue
            }

            // Only extract llama-server binary and dylibs
            let isServerBinary = localName == "llama-server"
            let isDylib = localName.hasSuffix(".dylib")
            guard isServerBinary || isDylib else {
                offset += ((fileSize + 511) / 512) * 512
                continue
            }

            let destPath = directory.appendingPathComponent(localName)

            if typeFlag == UInt8(ascii: "2") {
                // Symlink
                try? FileManager.default.removeItem(at: destPath)
                try FileManager.default.createSymbolicLink(atPath: destPath.path, withDestinationPath: linkTarget)
                Logger.debug("Extracted symlink: \(localName) -> \(linkTarget)", category: Logger.processing)
                extractedCount += 1
            } else if typeFlag == UInt8(ascii: "0") || typeFlag == 0 {
                // Regular file
                guard offset + fileSize <= tarData.count else {
                    throw LlamaServerError.downloadFailed("Tar archive is truncated at file: \(localName)")
                }
                let fileData = tarData[offset..<(offset + fileSize)]
                try? FileManager.default.removeItem(at: destPath)
                try fileData.write(to: destPath)

                // Make the server binary executable
                if isServerBinary {
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath.path)
                }

                Logger.debug("Extracted file: \(localName) (\(fileSize) bytes)", category: Logger.processing)
                extractedCount += 1
            }

            // Advance past file data (rounded up to 512-byte blocks)
            offset += ((fileSize + 511) / 512) * 512
        }

        // Verify the binary exists
        let serverPath = directory.appendingPathComponent("llama-server").path
        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw LlamaServerError.downloadFailed("llama-server binary not found after extraction (\(extractedCount) files extracted)")
        }

        // Remove quarantine extended attribute from all extracted files.
        // macOS adds com.apple.quarantine to downloaded files, which prevents execution
        // with a misleading "The file doesn't exist" error from Process.run().
        if let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in contents {
                removexattr(file.path, "com.apple.quarantine", 0)
            }
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: serverPath)
        Logger.info("llama-server extracted successfully (\(extractedCount) files, permissions: \(String(describing: attrs[.posixPermissions])))", category: Logger.processing)
    }

    /// Decompress gzip data using zlib (available on all Apple platforms)
    private static func decompressGzip(_ data: Data) throws -> Data {
        // Gzip header: 1f 8b
        guard data.count > 2, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else {
            throw LlamaServerError.downloadFailed("Not a valid gzip file")
        }

        var result = Data()
        result.reserveCapacity(data.count * 4)

        // Copy data into a contiguous byte array for zlib
        let inputBytes = [UInt8](data)
        let bufferSize = 65536
        var outputBuffer = [UInt8](repeating: 0, count: bufferSize)

        var stream = z_stream()
        stream.next_in = UnsafeMutablePointer(mutating: inputBytes)
        stream.avail_in = UInt32(inputBytes.count)

        // windowBits = 15 + 32 tells zlib to auto-detect gzip or zlib format
        let initResult = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else {
            throw LlamaServerError.downloadFailed("zlib inflateInit2 failed: \(initResult)")
        }
        defer { inflateEnd(&stream) }

        var inflateStatus: Int32 = Z_OK
        while inflateStatus != Z_STREAM_END {
            inflateStatus = outputBuffer.withUnsafeMutableBufferPointer { buf in
                stream.next_out = buf.baseAddress
                stream.avail_out = UInt32(bufferSize)
                return inflate(&stream, Z_NO_FLUSH)
            }
            let produced = bufferSize - Int(stream.avail_out)
            if produced > 0 {
                result.append(outputBuffer, count: produced)
            }
            if inflateStatus != Z_OK && inflateStatus != Z_STREAM_END {
                throw LlamaServerError.downloadFailed("zlib inflate failed: \(inflateStatus)")
            }
        }

        return result
    }

    /// Re-download llama-server, replacing any existing binary
    func updateLlamaServer() async throws {
        // Remove existing binary so downloadLlamaServer installs fresh
        if let dir = llamaServerDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        try await downloadLlamaServer()
    }

    /// Cancel an in-progress binary download
    func cancelBinaryDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloadingBinary = false
        binaryDownloadProgress = nil
    }

    // MARK: - Server Lifecycle

    /// Start the llama-server with the given GGUF model
    func startServer(modelPath: URL) async throws {
        // If already running with same model, no-op
        if isRunning && loadedModelPath == modelPath {
            Logger.info("llama-server already running with requested model", category: Logger.processing)
            return
        }

        // Stop existing server if running
        if isRunning {
            stopServer()
        }

        isLoading = true
        error = nil

        // Auto-download binary if not available
        if findLlamaServerBinary() == nil {
            try await downloadLlamaServer()
        }

        guard let binaryPath = findLlamaServerBinary() else {
            let err = LlamaServerError.binaryNotFound
            self.error = err
            isLoading = false
            throw err
        }

        // Find available port
        guard let port = await findAvailablePort() else {
            let err = LlamaServerError.portConflict
            self.error = err
            isLoading = false
            throw err
        }
        serverPort = port

        let contextSize = ModelSettings.ggufContextSize

        Logger.info("Starting llama-server on port \(port) with model: \(modelPath.lastPathComponent), ctx: \(contextSize)", category: Logger.processing)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "--model", modelPath.path,
            "--port", String(port),
            "--host", "127.0.0.1",
            "--ctx-size", String(contextSize),
            "--n-gpu-layers", "99"
        ]

        // Set environment so dylibs next to the binary are found
        let binaryDir = (binaryPath as NSString).deletingLastPathComponent
        process.environment = ProcessInfo.processInfo.environment
        process.currentDirectoryURL = URL(fileURLWithPath: binaryDir)

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        do {
            try process.run()
            serverProcess = process
            loadedModelPath = modelPath

            // Poll /health until ready (max ~30 seconds)
            let ready = await pollHealthEndpoint(port: port, maxAttempts: 60, interval: 0.5)
            if ready {
                isRunning = true
                isLoading = false
                Logger.info("llama-server is ready on port \(port)", category: Logger.processing)
            } else {
                stopServer()
                let err = LlamaServerError.startupTimeout
                self.error = err
                isLoading = false
                throw err
            }
        } catch let err as LlamaServerError {
            isLoading = false
            throw err
        } catch {
            Logger.error("Failed to start llama-server", error: error, category: Logger.processing)
            self.error = error
            isLoading = false
            throw error
        }
    }

    /// Stop the running llama-server
    func stopServer() {
        guard let process = serverProcess, process.isRunning else {
            isRunning = false
            loadedModelPath = nil
            serverProcess = nil
            return
        }

        Logger.info("Stopping llama-server", category: Logger.processing)
        process.terminate()

        // Give it a moment to terminate gracefully
        DispatchQueue.global().async {
            process.waitUntilExit()
        }

        serverProcess = nil
        isRunning = false
        loadedModelPath = nil
    }

    /// Restart with a new model
    func restartWithModel(modelPath: URL) async throws {
        stopServer()
        try await startServer(modelPath: modelPath)
    }

    // MARK: - Chat Completion API

    /// Send a chat completion request and stream the response
    func sendChatCompletion(
        messages: [[String: String]],
        temperature: Double = 0.7,
        maxTokens: Int = 2000
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "http://127.0.0.1:\(serverPort)/v1/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body: [String: Any] = [
                        "messages": messages,
                        "temperature": temperature,
                        "max_tokens": maxTokens,
                        "stream": true
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: LlamaServerError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))
                        if data == "[DONE]" { break }

                        guard let jsonData = data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func findLlamaServerBinary() -> String? {
        // Check bundle resources first
        if let bundlePath = Bundle.main.path(forResource: "llama-server", ofType: nil) {
            return bundlePath
        }
        // Check bin directory in bundle
        if let bundlePath = Bundle.main.resourcePath {
            let binPath = (bundlePath as NSString).appendingPathComponent("bin/llama-server")
            if FileManager.default.fileExists(atPath: binPath) {
                return binPath
            }
        }
        // Check downloaded location in Application Support
        // Note: use fileExists instead of isExecutableFile — the sandbox may report
        // downloaded binaries as non-executable even when they have +x permissions.
        if let dir = llamaServerDirectory {
            let downloadedPath = dir.appendingPathComponent("llama-server").path
            if FileManager.default.fileExists(atPath: downloadedPath) {
                // Strip quarantine on every lookup — macOS blocks execution of
                // quarantined files with a misleading "file doesn't exist" error.
                removexattr(downloadedPath, "com.apple.quarantine", 0)
                return downloadedPath
            }
        }
        // Fall back to system-installed llama-server (e.g. Homebrew, for development)
        let systemPaths = [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server"
        ]
        for path in systemPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                Logger.info("Using system llama-server at \(path)", category: Logger.processing)
                return path
            }
        }
        Logger.info("llama-server binary not found, download required", category: Logger.processing)
        return nil
    }

    private func findAvailablePort() async -> Int? {
        for port in portRange {
            let available = await checkPortAvailable(port)
            if available {
                return port
            }
        }
        return nil
    }

    private func checkPortAvailable(_ port: Int) async -> Bool {
        // Try connecting — if it fails, port is available
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            // If we get a response, something is already on this port
            _ = response
            return false
        } catch {
            // Connection refused = port is available
            return true
        }
    }

    private func pollHealthEndpoint(port: Int, maxAttempts: Int, interval: TimeInterval) async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!

        for _ in 0..<maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // Check if status is "ok" in the JSON response
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String, status == "ok" {
                        return true
                    }
                    // Some versions just return 200 without JSON
                    return true
                }
            } catch {
                // Server not ready yet
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return false
    }

    nonisolated deinit {}
}

// MARK: - Errors

enum LlamaServerError: LocalizedError {
    case binaryNotFound
    case portConflict
    case startupTimeout
    case requestFailed(String)
    case serverNotRunning
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "llama-server binary not found. Please check your internet connection and try again."
        case .portConflict:
            return "Could not find an available port for llama-server (tried 8081-8089)."
        case .startupTimeout:
            return "llama-server failed to start within 30 seconds. The model may be too large for available memory."
        case .requestFailed(let reason):
            return "Chat request failed: \(reason)"
        case .serverNotRunning:
            return "llama-server is not running. Please ensure a GGUF model is selected and downloaded."
        case .downloadFailed(let reason):
            return "Failed to download llama-server: \(reason)"
        }
    }
}
