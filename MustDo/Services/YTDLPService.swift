import Foundation
import AppKit

@MainActor
final class YTDLPService: ObservableObject {
    static let shared = YTDLPService()

    enum YTDLPError: LocalizedError {
        case binaryMissing
        case nonZeroExit(Int32, String)
        case noOutputFile
        var errorDescription: String? {
            switch self {
            case .binaryMissing:
                return "yt-dlp binary is not bundled. Run scripts/fetch_ytdlp.sh."
            case .nonZeroExit(let code, let msg):
                return "yt-dlp exited \(code): \(msg)"
            case .noOutputFile:
                return "yt-dlp finished but no output file was found."
            }
        }
    }

    private init() {}

    private var binaryURL: URL? {
        Bundle.main.url(forResource: "yt-dlp", withExtension: nil)
    }

    var isAvailable: Bool { binaryURL != nil }

    struct VideoInfo: Decodable {
        let title: String?
        let duration: Double?
        let thumbnail: String?
        let webpage_url: String?
        let uploader: String?
    }

    func fetchInfo(url: String) async throws -> VideoInfo {
        guard let bin = binaryURL else { throw YTDLPError.binaryMissing }
        let process = Process()
        process.executableURL = bin
        process.arguments = ["-J", "--no-warnings", "--no-playlist", url]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? ""
            throw YTDLPError.nonZeroExit(process.terminationStatus, msg)
        }
        let info = try JSONDecoder().decode(VideoInfo.self, from: outData)
        return info
    }

    /// Download video and thumbnail. Returns (storedVideoName, storedThumbName?).
    /// Progress callback receives a value 0..1 (or nil if unknown).
    func download(
        url: String,
        progress: @escaping (Double?) -> Void
    ) async throws -> (videoName: String, thumbnailName: String?) {
        guard let bin = binaryURL else { throw YTDLPError.binaryMissing }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mustdo-ytdlp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputTemplate = tempDir.appendingPathComponent("%(id)s.%(ext)s").path

        let args = [
            "--no-playlist",
            "--no-warnings",
            "--newline",
            "--progress",
            "--write-thumbnail",
            "--convert-thumbnails", "jpg",
            "-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/best",
            "--merge-output-format", "mp4",
            "-o", outputTemplate,
            url
        ]

        let process = Process()
        process.executableURL = bin
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Stream stdout for progress parsing
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            // yt-dlp prints lines like "[download]  42.5% of ..."
            for raw in line.split(separator: "\n") {
                let s = String(raw)
                if let range = s.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) {
                    let pct = s[range].dropLast()
                    if let val = Double(pct) {
                        Task { @MainActor in progress(val / 100.0) }
                    }
                }
            }
        }

        try process.run()
        process.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? ""
            throw YTDLPError.nonZeroExit(process.terminationStatus, msg)
        }

        // Find the video file and the thumbnail file
        let files = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
        let videoExts: Set<String> = ["mp4", "mkv", "webm", "mov", "m4v"]
        let thumbExts: Set<String> = ["jpg", "jpeg", "png", "webp"]
        let videoFile = files.first { videoExts.contains($0.pathExtension.lowercased()) }
        let thumbFile = files.first { thumbExts.contains($0.pathExtension.lowercased()) }
        guard let video = videoFile else { throw YTDLPError.noOutputFile }

        let videoStored = try MediaStore.shared.importFile(at: video, preferredPrefix: "video")
        var thumbStored: String? = nil
        if let thumb = thumbFile {
            let t = try MediaStore.shared.importFile(at: thumb, preferredPrefix: "thumb")
            thumbStored = t.storedName
        }
        return (videoStored.storedName, thumbStored)
    }
}
