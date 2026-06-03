import Foundation
import AppKit

/// Self-updater backed by GitHub Releases (public repo, no auth).
///
/// Flow: check `releases/latest` → if the tag is newer than the running
/// version, automatically download the `.dmg` asset → flip to
/// `.readyToInstall` so the UI can show a one-click "Install & Relaunch"
/// banner → on install, mount the DMG, swap the app bundle in place via
/// a detached shell script, and relaunch.
@MainActor
final class UpdateService: ObservableObject {

    struct Release: Equatable {
        let version: String        // normalized, e.g. "1.1"
        let tag: String            // raw tag, e.g. "v1.1"
        let name: String
        let notes: String
        let dmgURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(progress: Double, release: Release)
        case readyToInstall(dmg: URL, release: Release)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let owner = "moerdowo"
    private let repo = "MustDo"
    private let downloader = FileDownloader()
    private var didCheckOnLaunch = false

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    // MARK: - Checking

    func checkOnLaunch() {
        guard !didCheckOnLaunch else { return }
        didCheckOnLaunch = true
        Task { await check(userInitiated: false) }
    }

    func checkManually() {
        Task { await check(userInitiated: true) }
    }

    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        if case .readyToInstall = state { return }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            if isNewer(release.version, than: currentVersion) {
                await download(release)
            } else {
                state = .upToDate
                if !userInitiated {
                    // Stay quiet on launch when already current.
                    state = .idle
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            if !userInitiated { state = .idle }
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MustDo-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let tag = json["tag_name"] as? String else { throw UpdateError.noTag }
        let name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag
        let notes = (json["body"] as? String) ?? ""
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        guard let dmgString = assets
            .compactMap({ $0["browser_download_url"] as? String })
            .first(where: { $0.lowercased().hasSuffix(".dmg") }),
              let dmgURL = URL(string: dmgString)
        else { throw UpdateError.noDMG }

        return Release(
            version: normalize(tag),
            tag: tag,
            name: name,
            notes: notes,
            dmgURL: dmgURL
        )
    }

    // MARK: - Downloading

    private func download(_ release: Release) async {
        state = .downloading(progress: 0, release: release)
        do {
            let dest = updatesDirectory().appendingPathComponent("MustDo-\(release.tag).dmg")
            try? FileManager.default.removeItem(at: dest)
            try await downloader.download(from: release.dmgURL, to: dest) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    if case .downloading = self.state {
                        self.state = .downloading(progress: progress, release: release)
                    }
                }
            }
            state = .readyToInstall(dmg: dest, release: release)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Installing

    func installAndRelaunch() {
        guard case .readyToInstall(let dmg, _) = state else { return }
        do {
            try performInstall(dmgPath: dmg.path)
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func performInstall(dmgPath: String) throws {
        // Mount the DMG to a private mountpoint.
        let mountPoint = "/tmp/MustDoUpdate-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.removeItem(atPath: mountPoint)
        try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", dmgPath, "-nobrowse", "-noverify", "-mountpoint", mountPoint]
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else { throw UpdateError.mountFailed }

        // Locate the .app inside the mounted volume.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: mountPoint)) ?? []
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError.appNotFoundInDMG
        }
        let srcApp = "\(mountPoint)/\(appName)"
        let destApp = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier

        // Detached script: wait for us to quit, swap the bundle, relaunch.
        let script = """
        #!/bin/bash
        APP_PID=\(pid)
        SRC=\"\(srcApp)\"
        DEST=\"\(destApp)\"
        MOUNT=\"\(mountPoint)\"
        while /bin/kill -0 "$APP_PID" 2>/dev/null; do /bin/sleep 0.3; done
        /bin/sleep 0.4
        /bin/rm -rf "$DEST"
        /usr/bin/ditto "$SRC" "$DEST"
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        /usr/bin/hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
        /bin/rm -rf "$MOUNT" 2>/dev/null || true
        /usr/bin/open "$DEST"
        /bin/rm -f "$0"
        """
        let scriptPath = "/tmp/mustdo-update-\(pid).sh"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        let run = Process()
        run.executableURL = URL(fileURLWithPath: "/bin/bash")
        run.arguments = [scriptPath]
        try run.run()
        // Do not wait — it outlives us and relaunches the new build.
    }

    // MARK: - Helpers

    func dismiss() {
        state = .idle
    }

    private func updatesDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MustDo", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Strips a leading "v" and any pre-release suffix.
    private func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        return s
    }

    /// Numeric, component-wise semver-ish comparison.
    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = normalize(current).split(separator: ".").map { Int($0) ?? 0 }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    enum UpdateError: LocalizedError {
        case badResponse, noTag, noDMG, mountFailed, appNotFoundInDMG
        var errorDescription: String? {
            switch self {
            case .badResponse: return "Couldn't reach GitHub releases."
            case .noTag: return "No release tag found."
            case .noDMG: return "Latest release has no .dmg asset."
            case .mountFailed: return "Couldn't mount the update disk image."
            case .appNotFoundInDMG: return "No app found inside the update image."
            }
        }
    }
}

/// URLSession download-task wrapper that reports progress and moves the
/// finished file to a destination, bridged to async/await.
final class FileDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var progressHandler: ((Double) -> Void)?
    private var destination: URL?
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    func download(from url: URL, to dest: URL, progress: @escaping (Double) -> Void) async throws {
        self.progressHandler = progress
        self.destination = dest
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            var req = URLRequest(url: url)
            req.setValue("MustDo-Updater", forHTTPHeaderField: "User-Agent")
            session.downloadTask(with: req).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(p)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let dest = destination else { return }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
