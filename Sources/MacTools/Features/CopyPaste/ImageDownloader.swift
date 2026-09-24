import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downloads images from links (⌘D): probe type/size with HEAD, download to a temp file with
/// an optional size cap, then verify the bytes really are an image.
enum ImageDownloader {
    /// A single `http(s)` URL making up the whole (trimmed) text, else nil.
    static func link(in text: String?) -> URL? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
              t.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: t), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    enum Probe {
        /// Looks like an image (or the server didn't say); `size` when the server reported it.
        case candidate(size: Int64?)
        /// The server says it's something else (e.g. an HTML page).
        case notImage(String)
        case failed(String)
    }

    /// HEAD request: the Content-Type decides "not an image"; Content-Length gives the size.
    /// Servers that reject HEAD or omit headers yield `.candidate(size: nil)` — the download
    /// then verifies the bytes and enforces the cap itself.
    static func probe(_ url: URL) async -> Probe {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .candidate(size: nil)
            }
            let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if type.hasPrefix("text/") || type.contains("json") || (type.contains("xml") && !type.contains("svg")) {
                return .notImage(type.components(separatedBy: ";").first ?? type)
            }
            let size = http.expectedContentLength > 0 ? http.expectedContentLength : nil
            return .candidate(size: size)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    enum Download {
        /// Verified image in a temp file (caller moves it), with its real file extension.
        case image(file: URL, ext: String)
        /// Went over `cap` while downloading (size wasn't known up front).
        case tooLarge
        case notImage
        case failed(String)
    }

    /// Download to a temp file, aborting once more than `cap` bytes arrive (nil = no cap).
    static func download(_ url: URL, cap: Int64?) async -> Download {
        let result = await CappedDownload(url: url, cap: cap).run()
        switch result {
        case .failure(let error) where error is CappedDownload.TooLarge:
            return .tooLarge
        case .failure(let error):
            return .failed(error.localizedDescription)
        case .success(let file):
            guard let ext = imageExtension(of: file) else {
                try? FileManager.default.removeItem(at: file)
                return .notImage
            }
            return .image(file: file, ext: ext)
        }
    }

    /// File extension for the image format actually contained in `file` (nil if not an image).
    static func imageExtension(of file: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
              CGImageSourceGetCount(src) > 0,
              let type = CGImageSourceGetType(src) as String?,
              let ext = UTType(type)?.preferredFilenameExtension else { return nil }
        return ext
    }

    /// Display name from the link's file name, with the extension of the real format.
    static func name(for url: URL, ext: String) -> String {
        let last = url.lastPathComponent
        let base = last == "/" ? "" : (last as NSString).deletingPathExtension
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(base.isEmpty ? "image" : String(base.prefix(120))).\(ext)"
    }
}

/// One download task with its own delegate, so it can stop as soon as the size cap is hit
/// and keep the bytes on disk (never in memory).
private final class CappedDownload: NSObject, URLSessionDownloadDelegate {
    struct TooLarge: Error {}

    private let url: URL
    private let cap: Int64?
    private var continuation: CheckedContinuation<Result<URL, Error>, Never>?
    private var finished = false
    private var session: URLSession?

    init(url: URL, cap: Int64?) {
        self.url = url
        self.cap = cap
    }

    func run() async -> Result<URL, Error> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()
        continuation?.resume(returning: result)
        continuation = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let cap, totalBytesWritten > cap || totalBytesExpectedToWrite > cap {
            downloadTask.cancel()
            finish(.failure(TooLarge()))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // `location` is deleted when this returns — move it somewhere we own first.
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(NSError(domain: "mac-tools", code: http.statusCode,
                                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])))
            return
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-tools-download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            finish(.success(dest))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
