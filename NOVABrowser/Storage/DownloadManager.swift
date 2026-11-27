import Foundation
import WebKit

enum DownloadState: Codable, Equatable {
    case downloading
    case completed
    case failed(String)
    case cancelled
}

struct DownloadItem: Identifiable, Codable, Equatable {
    let id: UUID
    var filename: String
    var sourceURLString: String
    var localFilename: String?
    var totalBytes: Int64
    var receivedBytes: Int64
    var progress: Double
    var state: DownloadState
    var createdAt: Date

    var isVideo: Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(ext)
    }

    var formattedProgress: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        if totalBytes > 0 {
            return "\(formatter.string(fromByteCount: receivedBytes)) / \(formatter.string(fromByteCount: totalBytes))"
        } else if receivedBytes > 0 {
            return formatter.string(fromByteCount: receivedBytes)
        }
        return state == .completed ? "Completado" : "Preparando..."
    }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published var items: [DownloadItem] = []

    let downloadsDirectory: URL
    private let indexURL: URL
    private var wkDownloads: [UUID: WKDownload] = [:]
    private var wkDownloadIDs: [ObjectIdentifier: UUID] = [:]
    private var wkProgressObservations: [UUID: NSKeyValueObservation] = [:]

    private var urlSessionTasks: [UUID: URLSessionDownloadTask] = [:]
    private var urlTaskIDs: [Int: UUID] = [:]
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    var activeDownloadsCount: Int {
        items.filter { $0.state == .downloading }.count
    }

    override init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.downloadsDirectory = docs.appendingPathComponent("Descargas", isDirectory: true)
        self.indexURL = downloadsDirectory.appendingPathComponent(".downloads_index.json")
        super.init()

        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        loadPersistedDownloads()
    }

    func localFileURL(for item: DownloadItem) -> URL? {
        guard let localFilename = item.localFilename else { return nil }
        let url = downloadsDirectory.appendingPathComponent(localFilename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func attachWKDownload(_ download: WKDownload, initialURL: URL?) {
        let id = UUID()
        let fallbackName = initialURL?.lastPathComponent.isEmpty == false
            ? (initialURL?.lastPathComponent ?? "archivo")
            : "descarga"
        let item = DownloadItem(
            id: id,
            filename: fallbackName,
            sourceURLString: initialURL?.absoluteString ?? "",
            localFilename: nil,
            totalBytes: 0,
            receivedBytes: 0,
            progress: 0,
            state: .downloading,
            createdAt: Date()
        )
        items.insert(item, at: 0)
        wkDownloads[id] = download
        wkDownloadIDs[ObjectIdentifier(download)] = id
        download.delegate = self

        let observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] prog, _ in
            let fraction = prog.fractionCompleted
            let completed = prog.completedUnitCount
            let total = prog.totalUnitCount
            Task { @MainActor in
                self?.updateProgress(id: id, fraction: fraction, received: completed, total: total)
            }
        }
        wkProgressObservations[id] = observation
    }

    func startDirectDownload(url: URL, suggestedFilename: String? = nil) {
        let id = UUID()
        let rawName = suggestedFilename ?? (url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent)
        let cleanName = sanitizeFilename(rawName)
        let item = DownloadItem(
            id: id,
            filename: cleanName,
            sourceURLString: url.absoluteString,
            localFilename: nil,
            totalBytes: 0,
            receivedBytes: 0,
            progress: 0,
            state: .downloading,
            createdAt: Date()
        )
        items.insert(item, at: 0)

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPad; CPU OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let task = urlSession.downloadTask(with: request)
        urlSessionTasks[id] = task
        urlTaskIDs[task.taskIdentifier] = id
        task.resume()
    }

    func cancelDownload(id: UUID) {
        if let wk = wkDownloads.removeValue(forKey: id) {
            wkDownloadIDs.removeValue(forKey: ObjectIdentifier(wk))
            wk.cancel { _ in }
        }
        wkProgressObservations[id]?.invalidate()
        wkProgressObservations.removeValue(forKey: id)

        if let task = urlSessionTasks.removeValue(forKey: id) {
            urlTaskIDs.removeValue(forKey: task.taskIdentifier)
            task.cancel()
        }

        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].state = .cancelled
            savePersistedDownloads()
        }
    }

    func deleteDownload(_ item: DownloadItem) {
        if item.state == .downloading {
            cancelDownload(id: item.id)
        }
        if let url = localFileURL(for: item) {
            try? FileManager.default.removeItem(at: url)
        }
        items.removeAll { $0.id == item.id }
        savePersistedDownloads()
    }

    func clearFinished() {
        let toRemove = items.filter { $0.state != .downloading }
        for item in toRemove {
            if let url = localFileURL(for: item) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        items.removeAll { $0.state != .downloading }
        savePersistedDownloads()
    }

    private func updateProgress(id: UUID, fraction: Double, received: Int64, total: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].progress = min(max(fraction, 0), 1)
        items[idx].receivedBytes = max(0, received)
        if total > 0 {
            items[idx].totalBytes = total
        }
    }

    private func uniqueDestination(for rawFilename: String) -> URL {
        let sanitized = sanitizeFilename(rawFilename)
        let ext = (sanitized as NSString).pathExtension
        let base = (sanitized as NSString).deletingPathExtension

        var candidate = downloadsDirectory.appendingPathComponent(sanitized)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            candidate = downloadsDirectory.appendingPathComponent(nextName)
            counter += 1
        }
        return candidate
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "archivo" : cleaned
    }

    private func loadPersistedDownloads() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var loaded = try? decoder.decode([DownloadItem].self, from: data) else { return }
        loaded = loaded.compactMap { item in
            var copy = item
            if copy.state == .downloading {
                copy.state = .cancelled
            }
            if copy.state == .completed, localFileURL(for: copy) == nil {
                return nil
            }
            return copy
        }
        items = loaded
    }

    private func savePersistedDownloads() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}

extension DownloadManager: WKDownloadDelegate {
    nonisolated func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        Task { @MainActor in
            let id = self.wkDownloadIDs[ObjectIdentifier(download)]
            let dest = self.uniqueDestination(for: suggestedFilename)
            if let id = id, let idx = self.items.firstIndex(where: { $0.id == id }) {
                self.items[idx].filename = dest.lastPathComponent
                self.items[idx].localFilename = dest.lastPathComponent
                if response.expectedContentLength > 0 {
                    self.items[idx].totalBytes = response.expectedContentLength
                }
            }
            completionHandler(dest)
        }
    }

    nonisolated func downloadDidFinish(_ download: WKDownload) {
        Task { @MainActor in
            guard let id = self.wkDownloadIDs.removeValue(forKey: ObjectIdentifier(download)) else { return }
            self.wkDownloads.removeValue(forKey: id)
            self.wkProgressObservations[id]?.invalidate()
            self.wkProgressObservations.removeValue(forKey: id)

            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                self.items[idx].progress = 1.0
                self.items[idx].state = .completed
                if let url = self.localFileURL(for: self.items[idx]),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    self.items[idx].totalBytes = size
                    self.items[idx].receivedBytes = size
                }
                self.savePersistedDownloads()
            }
        }
    }

    nonisolated func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        Task { @MainActor in
            guard let id = self.wkDownloadIDs.removeValue(forKey: ObjectIdentifier(download)) else { return }
            self.wkDownloads.removeValue(forKey: id)
            self.wkProgressObservations[id]?.invalidate()
            self.wkProgressObservations.removeValue(forKey: id)

            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                if self.items[idx].state != .cancelled {
                    self.items[idx].state = .failed(error.localizedDescription)
                }
                self.savePersistedDownloads()
            }
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskID = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let id = self.urlTaskIDs[taskID] else { return }
            let fraction = totalBytesExpectedToWrite > 0
                ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                : 0
            self.updateProgress(id: id, fraction: fraction, received: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskID = downloadTask.taskIdentifier
        let suggested = downloadTask.response?.suggestedFilename
        let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var stagedToTemp = (try? FileManager.default.moveItem(at: location, to: tempCopy)) != nil
        if !stagedToTemp {
            stagedToTemp = (try? FileManager.default.copyItem(at: location, to: tempCopy)) != nil
        }

        Task { @MainActor in
            guard let id = self.urlTaskIDs.removeValue(forKey: taskID) else {
                try? FileManager.default.removeItem(at: tempCopy)
                return
            }
            self.urlSessionTasks.removeValue(forKey: id)
            guard let idx = self.items.firstIndex(where: { $0.id == id }) else {
                try? FileManager.default.removeItem(at: tempCopy)
                return
            }

            let targetName = suggested ?? self.items[idx].filename
            let dest = self.uniqueDestination(for: targetName)
            do {
                guard stagedToTemp else {
                    throw NSError(domain: "NOVADownload", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo guardar el archivo temporal"])
                }
                try FileManager.default.moveItem(at: tempCopy, to: dest)
                self.items[idx].filename = dest.lastPathComponent
                self.items[idx].localFilename = dest.lastPathComponent
                self.items[idx].progress = 1.0
                self.items[idx].state = .completed
                if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
                   let size = attrs[.size] as? Int64 {
                    self.items[idx].totalBytes = size
                    self.items[idx].receivedBytes = size
                }
            } catch {
                self.items[idx].state = .failed(error.localizedDescription)
            }
            self.savePersistedDownloads()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error else { return }
        let taskID = task.taskIdentifier
        Task { @MainActor in
            guard let id = self.urlTaskIDs.removeValue(forKey: taskID) else { return }
            self.urlSessionTasks.removeValue(forKey: id)
            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                let nsErr = error as NSError
                if nsErr.code == NSURLErrorCancelled {
                    self.items[idx].state = .cancelled
                } else {
                    self.items[idx].state = .failed(error.localizedDescription)
                }
                self.savePersistedDownloads()
            }
        }
    }
}
