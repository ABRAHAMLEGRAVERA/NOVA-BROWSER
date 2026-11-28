import Foundation
import WebKit

enum DownloadState: Codable, Equatable {
    case downloading
    case paused
    case completed
    case failed(String)
    case cancelled

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct DownloadSegment: Codable, Equatable {
    let index: Int
    let startByte: Int64
    let endByte: Int64
    var downloadedBytes: Int64
    var isCompleted: Bool

    var totalSegmentBytes: Int64 {
        max(0, endByte - startByte + 1)
    }
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
    var supportsResume: Bool
    var activeConnections: Int
    var segments: [DownloadSegment]?
    var resumeDataFilename: String?
    var isWKResumeData: Bool
    var speedBytesPerSecond: Double

    enum CodingKeys: String, CodingKey {
        case id, filename, sourceURLString, localFilename, totalBytes,
             receivedBytes, progress, state, createdAt, supportsResume,
             activeConnections, segments, resumeDataFilename, isWKResumeData
    }

    init(
        id: UUID = UUID(),
        filename: String,
        sourceURLString: String,
        localFilename: String? = nil,
        totalBytes: Int64 = 0,
        receivedBytes: Int64 = 0,
        progress: Double = 0,
        state: DownloadState = .downloading,
        createdAt: Date = Date(),
        supportsResume: Bool = false,
        activeConnections: Int = 1,
        segments: [DownloadSegment]? = nil,
        resumeDataFilename: String? = nil,
        isWKResumeData: Bool = false,
        speedBytesPerSecond: Double = 0
    ) {
        self.id = id
        self.filename = filename
        self.sourceURLString = sourceURLString
        self.localFilename = localFilename
        self.totalBytes = totalBytes
        self.receivedBytes = receivedBytes
        self.progress = progress
        self.state = state
        self.createdAt = createdAt
        self.supportsResume = supportsResume
        self.activeConnections = activeConnections
        self.segments = segments
        self.resumeDataFilename = resumeDataFilename
        self.isWKResumeData = isWKResumeData
        self.speedBytesPerSecond = speedBytesPerSecond
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        filename = try c.decode(String.self, forKey: .filename)
        sourceURLString = try c.decode(String.self, forKey: .sourceURLString)
        localFilename = try c.decodeIfPresent(String.self, forKey: .localFilename)
        totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        receivedBytes = try c.decodeIfPresent(Int64.self, forKey: .receivedBytes) ?? 0
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        state = try c.decodeIfPresent(DownloadState.self, forKey: .state) ?? .cancelled
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        supportsResume = try c.decodeIfPresent(Bool.self, forKey: .supportsResume) ?? false
        activeConnections = try c.decodeIfPresent(Int.self, forKey: .activeConnections) ?? 1
        segments = try c.decodeIfPresent([DownloadSegment].self, forKey: .segments)
        resumeDataFilename = try c.decodeIfPresent(String.self, forKey: .resumeDataFilename)
        isWKResumeData = try c.decodeIfPresent(Bool.self, forKey: .isWKResumeData) ?? false
        speedBytesPerSecond = 0
    }

    var isVideo: Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(ext)
    }

    var canPause: Bool {
        state == .downloading
    }

    var canResume: Bool {
        switch state {
        case .paused:
            return true
        case .failed:
            return supportsResume || (segments?.isEmpty == false) || resumeDataFilename != nil || URL(string: sourceURLString) != nil
        default:
            return false
        }
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

    var formattedSpeed: String? {
        guard state == .downloading, speedBytesPerSecond >= 512 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(speedBytesPerSecond)))/s"
    }
}

private final class SegmentedTaskContext {
    let downloadID: UUID
    let segmentIndex: Int
    var fileHandle: FileHandle?
    var downloadedBytes: Int64

    init(downloadID: UUID, segmentIndex: Int, downloadedBytes: Int64) {
        self.downloadID = downloadID
        self.segmentIndex = segmentIndex
        self.downloadedBytes = downloadedBytes
    }
}

private final class SegmentedBatchState {
    let downloadID: UUID
    let sourceURL: URL
    let filename: String
    let totalBytes: Int64
    var segments: [DownloadSegment]
    var taskContexts: [Int: SegmentedTaskContext] = [:]
    var activeTasks: [Int: URLSessionDataTask] = [:]
    var isStopped = false
    var lastUIReportTime: CFAbsoluteTime
    var lastReportedBytes: Int64

    init(downloadID: UUID, sourceURL: URL, filename: String, totalBytes: Int64, segments: [DownloadSegment]) {
        self.downloadID = downloadID
        self.sourceURL = sourceURL
        self.filename = filename
        self.totalBytes = totalBytes
        self.segments = segments
        self.lastReportedBytes = segments.reduce(0) { $0 + $1.downloadedBytes }
        self.lastUIReportTime = CFAbsoluteTimeGetCurrent()
    }
}

private final class SegmentedDownloadEngine: NSObject, URLSessionDataDelegate {
    private let partsDirectory: URL
    private let userAgent: String

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.novabrowser.segmentedEngine"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    private var batches: [UUID: SegmentedBatchState] = [:]
    private var taskToDownloadID: [Int: UUID] = [:]

    var onProgress: ((UUID, [DownloadSegment], Int64, Int64, Double) -> Void)?
    var onPaused: ((UUID, [DownloadSegment]) -> Void)?
    var onReadyMergedFile: ((UUID, URL, String, Int64) -> Void)?
    var onFailed: ((UUID, [DownloadSegment], String) -> Void)?

    init(partsDirectory: URL, userAgent: String) {
        self.partsDirectory = partsDirectory
        self.userAgent = userAgent
        super.init()
    }

    func startBatch(id: UUID, url: URL, filename: String, totalBytes: Int64, segments: [DownloadSegment]) {
        queue.addOperation { [weak self] in
            guard let self = self else { return }
            let jobDir = self.partsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)

            let batch = SegmentedBatchState(downloadID: id, sourceURL: url, filename: filename, totalBytes: totalBytes, segments: segments)
            self.batches[id] = batch

            var launched = 0
            for seg in segments where !seg.isCompleted {
                let resumeOffset = seg.startByte + seg.downloadedBytes
                guard resumeOffset <= seg.endByte else { continue }
                launched += 1

                let partURL = jobDir.appendingPathComponent("seg_\(seg.index).part")
                if !FileManager.default.fileExists(atPath: partURL.path) {
                    FileManager.default.createFile(atPath: partURL.path, contents: nil)
                }

                let ctx = SegmentedTaskContext(downloadID: id, segmentIndex: seg.index, downloadedBytes: seg.downloadedBytes)
                if let handle = try? FileHandle(forUpdating: partURL) {
                    _ = try? handle.seek(toOffset: UInt64(seg.downloadedBytes))
                    ctx.fileHandle = handle
                }

                var req = URLRequest(url: url)
                req.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
                req.setValue("bytes=\(resumeOffset)-\(seg.endByte)", forHTTPHeaderField: "Range")

                let task = self.session.dataTask(with: req)
                batch.taskContexts[task.taskIdentifier] = ctx
                batch.activeTasks[task.taskIdentifier] = task
                self.taskToDownloadID[task.taskIdentifier] = id
                task.resume()
            }

            if launched == 0 {
                self.finalizeBatch(batch)
            }
        }
    }

    func pauseBatch(id: UUID) {
        queue.addOperation { [weak self] in
            guard let self = self, let batch = self.batches.removeValue(forKey: id) else { return }
            batch.isStopped = true
            let snapshot = batch.segments
            for (taskID, task) in batch.activeTasks {
                task.cancel()
                self.taskToDownloadID.removeValue(forKey: taskID)
            }
            for (_, ctx) in batch.taskContexts {
                try? ctx.fileHandle?.synchronize()
                try? ctx.fileHandle?.close()
                ctx.fileHandle = nil
            }
            batch.activeTasks.removeAll()
            batch.taskContexts.removeAll()
            self.onPaused?(id, snapshot)
        }
    }

    func cancelBatch(id: UUID) {
        queue.addOperation { [weak self] in
            guard let self = self, let batch = self.batches.removeValue(forKey: id) else { return }
            batch.isStopped = true
            for (taskID, task) in batch.activeTasks {
                task.cancel()
                self.taskToDownloadID.removeValue(forKey: taskID)
            }
            for (_, ctx) in batch.taskContexts {
                try? ctx.fileHandle?.close()
                ctx.fileHandle = nil
            }
            batch.activeTasks.removeAll()
            batch.taskContexts.removeAll()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let taskID = dataTask.taskIdentifier
        guard let downloadID = taskToDownloadID[taskID],
              let batch = batches[downloadID],
              !batch.isStopped,
              let ctx = batch.taskContexts[taskID] else {
            return
        }

        ctx.fileHandle?.write(data)
        ctx.downloadedBytes += Int64(data.count)
        batch.segments[ctx.segmentIndex].downloadedBytes = ctx.downloadedBytes

        let now = CFAbsoluteTimeGetCurrent()
        let dt = now - batch.lastUIReportTime
        if dt >= 0.32 {
            let totalRec = batch.segments.reduce(0) { $0 + $1.downloadedBytes }
            let delta = max(0, totalRec - batch.lastReportedBytes)
            let speed = Double(delta) / dt
            batch.lastUIReportTime = now
            batch.lastReportedBytes = totalRec
            onProgress?(downloadID, batch.segments, totalRec, batch.totalBytes, speed)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskID = task.taskIdentifier
        guard let downloadID = taskToDownloadID.removeValue(forKey: taskID),
              let batch = batches[downloadID],
              let ctx = batch.taskContexts.removeValue(forKey: taskID) else {
            return
        }
        batch.activeTasks.removeValue(forKey: taskID)
        try? ctx.fileHandle?.synchronize()
        try? ctx.fileHandle?.close()
        ctx.fileHandle = nil

        if batch.isStopped {
            return
        }

        if let error = error {
            let nsErr = error as NSError
            if nsErr.code == NSURLErrorCancelled { return }

            batch.isStopped = true
            for (otherID, otherTask) in batch.activeTasks {
                otherTask.cancel()
                taskToDownloadID.removeValue(forKey: otherID)
            }
            for (_, otherCtx) in batch.taskContexts {
                try? otherCtx.fileHandle?.synchronize()
                try? otherCtx.fileHandle?.close()
                otherCtx.fileHandle = nil
            }
            batch.activeTasks.removeAll()
            batch.taskContexts.removeAll()
            let snapshot = batch.segments
            batches.removeValue(forKey: downloadID)
            onFailed?(downloadID, snapshot, error.localizedDescription)
            return
        }

        batch.segments[ctx.segmentIndex].isCompleted = true
        batch.segments[ctx.segmentIndex].downloadedBytes = ctx.downloadedBytes

        if batch.segments.allSatisfy({ $0.isCompleted }) {
            finalizeBatch(batch)
        }
    }

    private func finalizeBatch(_ batch: SegmentedBatchState) {
        guard !batch.isStopped else { return }
        let id = batch.downloadID
        let filename = batch.filename
        let totalExpected = batch.totalBytes
        let count = batch.segments.count
        let segmentsSnapshot = batch.segments
        let jobDir = partsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        batches.removeValue(forKey: id)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let tempMerged = FileManager.default.temporaryDirectory.appendingPathComponent("merge_\(id.uuidString)")
            FileManager.default.createFile(atPath: tempMerged.path, contents: nil)
            do {
                let outHandle = try FileHandle(forWritingTo: tempMerged)
                defer { try? outHandle.close() }

                for idx in 0..<count {
                    let partURL = jobDir.appendingPathComponent("seg_\(idx).part")
                    let inHandle = try FileHandle(forReadingFrom: partURL)
                    defer { try? inHandle.close() }
                    while true {
                        let chunk = inHandle.readData(ofLength: 262_144)
                        if chunk.isEmpty { break }
                        outHandle.write(chunk)
                    }
                }
                try outHandle.synchronize()
                self.onReadyMergedFile?(id, tempMerged, filename, totalExpected)
            } catch {
                try? FileManager.default.removeItem(at: tempMerged)
                self.onFailed?(id, segmentsSnapshot, error.localizedDescription)
            }
        }
    }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published var items: [DownloadItem] = []

    let downloadsDirectory: URL
    private let partsDirectory: URL
    private let indexURL: URL

    private static let safariUA = "Mozilla/5.0 (iPad; CPU OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1"
    private static let maxThreadsPerDownload = 4
    private static let minBytesForSegmentation: Int64 = 524_288

    private var wkDownloads: [UUID: WKDownload] = [:]
    private var wkDownloadIDs: [ObjectIdentifier: UUID] = [:]
    private var wkProgressObservations: [UUID: NSKeyValueObservation] = [:]
    private weak var lastWKWebView: WKWebView?

    private var urlSessionTasks: [UUID: URLSessionDownloadTask] = [:]
    private var urlTaskIDs: [Int: UUID] = [:]
    private var singleSpeedTrackers: [UUID: (time: CFAbsoluteTime, bytes: Int64)] = [:]
    private var probeTasks: [UUID: Task<Void, Never>] = [:]

    private let segmentedEngine: SegmentedDownloadEngine

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
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
        self.partsDirectory = downloadsDirectory.appendingPathComponent(".parts", isDirectory: true)
        self.indexURL = downloadsDirectory.appendingPathComponent(".downloads_index.json")
        self.segmentedEngine = SegmentedDownloadEngine(partsDirectory: partsDirectory, userAgent: Self.safariUA)
        super.init()

        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: partsDirectory, withIntermediateDirectories: true)
        bindSegmentedEngineCallbacks()
        loadPersistedDownloads()
    }

    private func bindSegmentedEngineCallbacks() {
        segmentedEngine.onProgress = { [weak self] id, segs, rec, total, speed in
            Task { @MainActor in
                self?.updateSegmentedProgress(id: id, segments: segs, totalReceived: rec, totalBytes: total, speed: speed)
            }
        }
        segmentedEngine.onPaused = { [weak self] id, segs in
            Task { @MainActor in
                guard let self = self, let i = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[i].segments = segs
                let rec = segs.reduce(0) { $0 + $1.downloadedBytes }
                self.items[i].receivedBytes = rec
                if self.items[i].totalBytes > 0 {
                    self.items[i].progress = Double(rec) / Double(self.items[i].totalBytes)
                }
                self.items[i].speedBytesPerSecond = 0
                self.items[i].state = .paused
                self.savePersistedDownloads()
            }
        }
        segmentedEngine.onReadyMergedFile = { [weak self] id, tempURL, filename, totalExpected in
            Task { @MainActor in
                guard let self = self else {
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }
                let dest = self.uniqueDestination(for: filename)
                do {
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    self.cleanupParts(for: id)
                    if let i = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[i].filename = dest.lastPathComponent
                        self.items[i].localFilename = dest.lastPathComponent
                        self.items[i].progress = 1.0
                        self.items[i].state = .completed
                        self.items[i].speedBytesPerSecond = 0
                        self.items[i].segments = nil
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
                           let size = attrs[.size] as? Int64 {
                            self.items[i].totalBytes = size
                            self.items[i].receivedBytes = size
                        } else {
                            self.items[i].totalBytes = totalExpected
                            self.items[i].receivedBytes = totalExpected
                        }
                        self.savePersistedDownloads()
                    }
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    if let i = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[i].state = .failed(error.localizedDescription)
                        self.savePersistedDownloads()
                    }
                }
            }
        }
        segmentedEngine.onFailed = { [weak self] id, segs, message in
            Task { @MainActor in
                guard let self = self, let i = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[i].segments = segs
                self.items[i].speedBytesPerSecond = 0
                if self.items[i].state == .downloading {
                    self.items[i].state = .failed(message)
                }
                self.savePersistedDownloads()
            }
        }
    }

    func localFileURL(for item: DownloadItem) -> URL? {
        guard let localFilename = item.localFilename else { return nil }
        let url = downloadsDirectory.appendingPathComponent(localFilename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - WKDownload Integration

    func attachWKDownload(_ download: WKDownload, initialURL: URL?, webView: WKWebView? = nil) {
        if let webView = webView {
            self.lastWKWebView = webView
        }
        let urlString = initialURL?.absoluteString ?? ""
        if !urlString.isEmpty && items.contains(where: { $0.state == .downloading && $0.sourceURLString == urlString }) {
            download.cancel { _ in }
            return
        }
        let id = UUID()
        let fallbackName = initialURL?.lastPathComponent.isEmpty == false
            ? (initialURL?.lastPathComponent ?? "archivo")
            : "descarga"
        let item = DownloadItem(
            id: id,
            filename: fallbackName,
            sourceURLString: urlString,
            state: .downloading,
            supportsResume: true,
            activeConnections: 1
        )
        items.insert(item, at: 0)
        bindWKDownload(download, to: id)
        savePersistedDownloads()
    }

    private func bindWKDownload(_ download: WKDownload, to id: UUID) {
        wkDownloads[id] = download
        wkDownloadIDs[ObjectIdentifier(download)] = id
        download.delegate = self

        let observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] prog, _ in
            let fraction = prog.fractionCompleted
            let completed = prog.completedUnitCount
            let total = prog.totalUnitCount
            Task { @MainActor in
                self?.updateSingleProgress(id: id, fraction: fraction, received: completed, total: total)
            }
        }
        wkProgressObservations[id] = observation
    }

    // MARK: - Fast Multi-Thread Direct Downloads

    func startDirectDownload(url: URL, suggestedFilename: String? = nil) {
        let urlString = url.absoluteString
        if items.contains(where: { $0.state == .downloading && $0.sourceURLString == urlString }) {
            return
        }
        let id = UUID()
        let rawName = suggestedFilename ?? (url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent)
        let cleanName = sanitizeFilename(rawName)
        let item = DownloadItem(
            id: id,
            filename: cleanName,
            sourceURLString: urlString,
            state: .downloading,
            supportsResume: false,
            activeConnections: 1
        )
        items.insert(item, at: 0)
        savePersistedDownloads()

        probeAndLaunchDownload(id: id, url: url, filename: cleanName)
    }

    private func probeAndLaunchDownload(id: UUID, url: URL, filename: String) {
        probeTasks[id]?.cancel()
        probeTasks[id] = Task { [weak self] in
            guard let self = self else { return }
            let probe = await self.probeServerRangeSupport(for: url)
            if Task.isCancelled { return }

            guard let idx = self.items.firstIndex(where: { $0.id == id }),
                  self.items[idx].state == .downloading else { return }

            let finalName = probe.suggestedFilename.map { self.sanitizeFilename($0) } ?? filename
            self.items[idx].filename = finalName
            self.items[idx].supportsResume = probe.acceptsRanges

            if probe.totalBytes > 0 {
                self.items[idx].totalBytes = probe.totalBytes
            }

            if probe.acceptsRanges && probe.totalBytes >= Self.minBytesForSegmentation {
                let threads = probe.totalBytes >= 2_097_152 ? Self.maxThreadsPerDownload : 2
                let segments = self.buildSegments(totalBytes: probe.totalBytes, count: threads)
                self.items[idx].activeConnections = threads
                self.items[idx].segments = segments
                self.savePersistedDownloads()
                self.segmentedEngine.startBatch(id: id, url: url, filename: finalName, totalBytes: probe.totalBytes, segments: segments)
            } else {
                self.items[idx].activeConnections = 1
                self.savePersistedDownloads()
                self.launchSingleURLSessionDownload(id: id, url: url)
            }
        }
    }

    private struct ProbeResult {
        let acceptsRanges: Bool
        let totalBytes: Int64
        let suggestedFilename: String?
    }

    private func probeServerRangeSupport(for url: URL) async -> ProbeResult {
        var headReq = URLRequest(url: url)
        headReq.httpMethod = "HEAD"
        headReq.timeoutInterval = 10
        headReq.setValue(Self.safariUA, forHTTPHeaderField: "User-Agent")

        if let (_, resp) = try? await urlSession.data(for: headReq),
           let http = resp as? HTTPURLResponse,
           (200...299).contains(http.statusCode) {
            let acceptRanges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased().contains("bytes")
            let length = http.expectedContentLength
            if acceptRanges && length > 0 {
                return ProbeResult(acceptsRanges: true, totalBytes: length, suggestedFilename: http.suggestedFilename)
            }
        }

        var rangeReq = URLRequest(url: url)
        rangeReq.httpMethod = "GET"
        rangeReq.timeoutInterval = 12
        rangeReq.setValue(Self.safariUA, forHTTPHeaderField: "User-Agent")
        rangeReq.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        if let (_, resp) = try? await urlSession.data(for: rangeReq),
           let http = resp as? HTTPURLResponse {
            if http.statusCode == 206,
               let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
               let total = parseTotalBytes(fromContentRange: contentRange),
               total > 0 {
                return ProbeResult(acceptsRanges: true, totalBytes: total, suggestedFilename: http.suggestedFilename)
            }
            if (200...299).contains(http.statusCode), http.expectedContentLength > 0 {
                let acceptRanges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased().contains("bytes")
                return ProbeResult(acceptsRanges: acceptRanges, totalBytes: http.expectedContentLength, suggestedFilename: http.suggestedFilename)
            }
        }

        return ProbeResult(acceptsRanges: false, totalBytes: 0, suggestedFilename: nil)
    }

    private func parseTotalBytes(fromContentRange header: String) -> Int64? {
        guard let slash = header.lastIndex(of: "/") else { return nil }
        let tail = header[header.index(after: slash)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return Int64(tail)
    }

    private func buildSegments(totalBytes: Int64, count: Int) -> [DownloadSegment] {
        let safeCount = max(1, count)
        let chunkSize = totalBytes / Int64(safeCount)
        var result: [DownloadSegment] = []
        var offset: Int64 = 0
        for index in 0..<safeCount {
            let start = offset
            let end = (index == safeCount - 1) ? (totalBytes - 1) : (start + chunkSize - 1)
            result.append(DownloadSegment(index: index, startByte: start, endByte: end, downloadedBytes: 0, isCompleted: false))
            offset = end + 1
        }
        return result
    }

    private func launchSingleURLSessionDownload(id: UUID, url: URL) {
        var request = URLRequest(url: url)
        request.setValue(Self.safariUA, forHTTPHeaderField: "User-Agent")
        let task = urlSession.downloadTask(with: request)
        urlSessionTasks[id] = task
        urlTaskIDs[task.taskIdentifier] = id
        singleSpeedTrackers[id] = (CFAbsoluteTimeGetCurrent(), 0)
        task.resume()
    }

    // MARK: - Pause, Resume & Cancel

    func pauseDownload(id: UUID) {
        probeTasks[id]?.cancel()
        probeTasks.removeValue(forKey: id)

        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].state == .downloading else { return }
        items[idx].speedBytesPerSecond = 0

        if let wk = wkDownloads.removeValue(forKey: id) {
            wkDownloadIDs.removeValue(forKey: ObjectIdentifier(wk))
            wkProgressObservations[id]?.invalidate()
            wkProgressObservations.removeValue(forKey: id)
            wk.cancel { [weak self] resumeData in
                Task { @MainActor in
                    self?.storeResumeData(resumeData, for: id, isWK: true)
                    if let i = self?.items.firstIndex(where: { $0.id == id }) {
                        self?.items[i].state = .paused
                        self?.items[i].supportsResume = (resumeData != nil)
                        self?.savePersistedDownloads()
                    }
                }
            }
            return
        }

        if let task = urlSessionTasks.removeValue(forKey: id) {
            urlTaskIDs.removeValue(forKey: task.taskIdentifier)
            singleSpeedTrackers.removeValue(forKey: id)
            task.cancel { [weak self] resumeData in
                Task { @MainActor in
                    self?.storeResumeData(resumeData, for: id, isWK: false)
                    if let i = self?.items.firstIndex(where: { $0.id == id }) {
                        self?.items[i].state = .paused
                        if resumeData != nil {
                            self?.items[i].supportsResume = true
                        }
                        self?.savePersistedDownloads()
                    }
                }
            }
            return
        }

        items[idx].state = .paused
        segmentedEngine.pauseBatch(id: id)
    }

    func resumeDownload(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].canResume else { return }
        let item = items[idx]
        items[idx].state = .downloading
        items[idx].speedBytesPerSecond = 0

        if item.isWKResumeData,
           let resumeFile = item.resumeDataFilename,
           let data = try? Data(contentsOf: partsDirectory.appendingPathComponent(resumeFile)),
           let webView = lastWKWebView {
            try? FileManager.default.removeItem(at: partsDirectory.appendingPathComponent(resumeFile))
            items[idx].resumeDataFilename = nil
            items[idx].isWKResumeData = false
            savePersistedDownloads()
            webView.resumeDownload(fromResumeData: data) { [weak self] resumedDownload in
                Task { @MainActor in
                    self?.bindWKDownload(resumedDownload, to: id)
                }
            }
            return
        }

        if let segments = item.segments, !segments.isEmpty, let url = URL(string: item.sourceURLString), item.totalBytes > 0 {
            items[idx].activeConnections = max(1, segments.filter { !$0.isCompleted }.count)
            savePersistedDownloads()
            segmentedEngine.startBatch(id: id, url: url, filename: item.filename, totalBytes: item.totalBytes, segments: segments)
            return
        }

        if let resumeFile = item.resumeDataFilename,
           let data = try? Data(contentsOf: partsDirectory.appendingPathComponent(resumeFile)) {
            try? FileManager.default.removeItem(at: partsDirectory.appendingPathComponent(resumeFile))
            items[idx].resumeDataFilename = nil
            savePersistedDownloads()

            let task = urlSession.downloadTask(withResumeData: data)
            urlSessionTasks[id] = task
            urlTaskIDs[task.taskIdentifier] = id
            singleSpeedTrackers[id] = (CFAbsoluteTimeGetCurrent(), item.receivedBytes)
            task.resume()
            return
        }

        if let url = URL(string: item.sourceURLString) {
            savePersistedDownloads()
            probeAndLaunchDownload(id: id, url: url, filename: item.filename)
        } else {
            items[idx].state = .failed("Enlace no disponible para reanudar")
            savePersistedDownloads()
        }
    }

    func cancelDownload(id: UUID) {
        probeTasks[id]?.cancel()
        probeTasks.removeValue(forKey: id)

        if let wk = wkDownloads.removeValue(forKey: id) {
            wkDownloadIDs.removeValue(forKey: ObjectIdentifier(wk))
            wk.cancel { _ in }
        }
        wkProgressObservations[id]?.invalidate()
        wkProgressObservations.removeValue(forKey: id)

        if let task = urlSessionTasks.removeValue(forKey: id) {
            urlTaskIDs.removeValue(forKey: task.taskIdentifier)
            singleSpeedTrackers.removeValue(forKey: id)
            task.cancel()
        }

        segmentedEngine.cancelBatch(id: id)
        cleanupParts(for: id)

        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].state = .cancelled
            items[idx].speedBytesPerSecond = 0
            items[idx].segments = nil
            items[idx].resumeDataFilename = nil
            savePersistedDownloads()
        }
    }

    func deleteDownload(_ item: DownloadItem) {
        if item.state == .downloading {
            cancelDownload(id: item.id)
        } else {
            cleanupParts(for: item.id)
        }
        if let url = localFileURL(for: item) {
            try? FileManager.default.removeItem(at: url)
        }
        items.removeAll { $0.id == item.id }
        savePersistedDownloads()
    }

    func clearFinished() {
        let toRemove = items.filter { $0.state != .downloading && $0.state != .paused }
        for item in toRemove {
            cleanupParts(for: item.id)
            if let url = localFileURL(for: item) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        items.removeAll { $0.state == .completed || $0.state == .cancelled || $0.state.isFailed }
        savePersistedDownloads()
    }

    // MARK: - Helpers

    private func storeResumeData(_ data: Data?, for id: UUID, isWK: Bool) {
        guard let data = data, !data.isEmpty,
              let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let filename = "\(id.uuidString).resume"
        let dest = partsDirectory.appendingPathComponent(filename)
        if (try? data.write(to: dest, options: .atomic)) != nil {
            items[idx].resumeDataFilename = filename
            items[idx].isWKResumeData = isWK
        }
    }

    private func cleanupParts(for id: UUID) {
        let jobDir = partsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: jobDir)
        let resumeFile = partsDirectory.appendingPathComponent("\(id.uuidString).resume")
        try? FileManager.default.removeItem(at: resumeFile)
    }

    private func updateSingleProgress(id: UUID, fraction: Double, received: Int64, total: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].state == .downloading else { return }
        items[idx].progress = min(max(fraction, 0), 1)
        items[idx].receivedBytes = max(0, received)
        if total > 0 {
            items[idx].totalBytes = total
        }

        let now = CFAbsoluteTimeGetCurrent()
        if let prev = singleSpeedTrackers[id] {
            let dt = now - prev.time
            if dt >= 0.45 {
                let delta = max(0, received - prev.bytes)
                items[idx].speedBytesPerSecond = Double(delta) / dt
                singleSpeedTrackers[id] = (now, received)
            }
        } else {
            singleSpeedTrackers[id] = (now, received)
        }
    }

    private func updateSegmentedProgress(
        id: UUID,
        segments: [DownloadSegment],
        totalReceived: Int64,
        totalBytes: Int64,
        speed: Double
    ) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].state == .downloading else { return }
        items[idx].segments = segments
        items[idx].receivedBytes = totalReceived
        items[idx].totalBytes = totalBytes
        items[idx].progress = totalBytes > 0 ? min(1, Double(totalReceived) / Double(totalBytes)) : 0
        items[idx].speedBytesPerSecond = speed
        items[idx].activeConnections = max(1, segments.filter { !$0.isCompleted }.count)
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
                copy.state = (copy.segments != nil || copy.resumeDataFilename != nil || copy.supportsResume) ? .paused : .cancelled
            }
            copy.speedBytesPerSecond = 0
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

// MARK: - WKDownloadDelegate

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
            self.singleSpeedTrackers.removeValue(forKey: id)

            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                self.items[idx].progress = 1.0
                self.items[idx].state = .completed
                self.items[idx].speedBytesPerSecond = 0
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
            self.singleSpeedTrackers.removeValue(forKey: id)

            if let resumeData = resumeData {
                self.storeResumeData(resumeData, for: id, isWK: true)
            }
            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                self.items[idx].speedBytesPerSecond = 0
                if self.items[idx].state != .cancelled && self.items[idx].state != .paused {
                    self.items[idx].state = .failed(error.localizedDescription)
                }
                self.savePersistedDownloads()
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

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
            self.updateSingleProgress(id: id, fraction: fraction, received: totalBytesWritten, total: totalBytesExpectedToWrite)
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
            self.singleSpeedTrackers.removeValue(forKey: id)
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
                self.cleanupParts(for: id)
                self.items[idx].filename = dest.lastPathComponent
                self.items[idx].localFilename = dest.lastPathComponent
                self.items[idx].progress = 1.0
                self.items[idx].state = .completed
                self.items[idx].speedBytesPerSecond = 0
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
            self.singleSpeedTrackers.removeValue(forKey: id)
            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                self.items[idx].speedBytesPerSecond = 0
                let nsErr = error as NSError
                if let resumeData = nsErr.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    self.storeResumeData(resumeData, for: id, isWK: false)
                    self.items[idx].supportsResume = true
                }
                if nsErr.code == NSURLErrorCancelled {
                    if self.items[idx].state != .paused {
                        self.items[idx].state = .cancelled
                    }
                } else {
                    self.items[idx].state = .failed(error.localizedDescription)
                }
                self.savePersistedDownloads()
            }
        }
    }
}
