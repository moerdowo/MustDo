import Foundation
import AppKit
import UniformTypeIdentifiers

final class MediaStore {
    static let shared = MediaStore()

    let root: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "MustDo"
        let root = appSupport.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
    }

    func url(for name: String) -> URL {
        root.appendingPathComponent(name)
    }

    @discardableResult
    func importFile(at sourceURL: URL, preferredPrefix: String = "") throws -> (storedName: String, originalName: String) {
        let needsAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if needsAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let original = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension
        let unique = UUID().uuidString
        let stored = preferredPrefix.isEmpty
            ? (ext.isEmpty ? unique : "\(unique).\(ext)")
            : (ext.isEmpty ? "\(preferredPrefix)-\(unique)" : "\(preferredPrefix)-\(unique).\(ext)")
        let dest = url(for: stored)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return (stored, original)
    }

    func writeData(_ data: Data, extension ext: String, preferredPrefix: String = "") throws -> String {
        let unique = UUID().uuidString
        let stored = preferredPrefix.isEmpty
            ? "\(unique).\(ext)"
            : "\(preferredPrefix)-\(unique).\(ext)"
        let dest = url(for: stored)
        try data.write(to: dest)
        return stored
    }

    func deleteFile(named name: String) {
        let u = url(for: name)
        try? FileManager.default.removeItem(at: u)
    }
}

enum MediaKind {
    case video
    case audio
    case pdf
    case epub
    case mobi
    case otherDocument
    case other

    static func detect(from url: URL) -> MediaKind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "m4v", "mkv", "webm", "avi": return .video
        case "mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "opus": return .audio
        case "pdf": return .pdf
        case "epub": return .epub
        case "mobi", "azw", "azw3": return .mobi
        case "txt", "md", "rtf", "doc", "docx": return .otherDocument
        default:
            if let type = UTType(filenameExtension: ext) {
                if type.conforms(to: .movie) { return .video }
                if type.conforms(to: .audio) { return .audio }
                if type.conforms(to: .pdf) { return .pdf }
            }
            return .other
        }
    }
}
