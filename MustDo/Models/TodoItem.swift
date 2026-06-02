import Foundation
import SwiftData

enum MustCategory: String, Codable, CaseIterable, Identifiable {
    case mustDo
    case mustWatch
    case mustRead
    case mustListen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mustDo: return "Must Do"
        case .mustWatch: return "Must Watch"
        case .mustRead: return "Must Read"
        case .mustListen: return "Must Listen"
        }
    }

    var systemImage: String {
        switch self {
        case .mustDo: return "checklist"
        case .mustWatch: return "play.rectangle.fill"
        case .mustRead: return "book.fill"
        case .mustListen: return "headphones"
        }
    }
}

enum VideoDownloadStatus: String, Codable {
    case pending
    case downloading
    case downloaded
    case failed
    case notApplicable
}

enum ReadKind: String, Codable {
    case webURL
    case pdf
    case epub
    case mobi
    case otherFile
}

enum ListenKind: String, Codable {
    case podcastFeed
    case audioFile
    case audioURL
}

@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var categoryRaw: String
    var title: String
    var notes: String
    var createdAt: Date
    var completedAt: Date?
    var sortOrder: Double

    var sourceURLString: String?

    /// Absolute path to a file the user owns (dragged in / picked).
    /// We do NOT copy these — we reference them in place so the user can
    /// keep their library wherever they want and AVPlayer / PDFKit / etc.
    /// read the file directly.
    var filePath: String?

    /// Filename inside MediaStore for files MustDo itself produced
    /// (yt-dlp downloads, thumbnails). Stays alongside `filePath` so
    /// existing data continues to work and we can keep ownership of
    /// generated media.
    var storedFileName: String?
    var originalFileName: String?

    var videoStatusRaw: String?
    var videoProgress: Double?
    var thumbnailFileName: String?
    var durationSeconds: Double?

    var readKindRaw: String?

    var listenKindRaw: String?
    var lastFeedRefreshAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \PodcastEpisode.parent)
    var episodes: [PodcastEpisode]? = []

    init(
        id: UUID = UUID(),
        category: MustCategory,
        title: String,
        notes: String = "",
        createdAt: Date = .now,
        sortOrder: Double = 0,
        sourceURLString: String? = nil,
        storedFileName: String? = nil,
        originalFileName: String? = nil
    ) {
        self.id = id
        self.categoryRaw = category.rawValue
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.sourceURLString = sourceURLString
        self.storedFileName = storedFileName
        self.originalFileName = originalFileName
    }

    var category: MustCategory {
        get { MustCategory(rawValue: categoryRaw) ?? .mustDo }
        set { categoryRaw = newValue.rawValue }
    }

    var videoStatus: VideoDownloadStatus {
        get { VideoDownloadStatus(rawValue: videoStatusRaw ?? "") ?? .notApplicable }
        set { videoStatusRaw = newValue.rawValue }
    }

    var readKind: ReadKind? {
        get { readKindRaw.flatMap { ReadKind(rawValue: $0) } }
        set { readKindRaw = newValue?.rawValue }
    }

    var listenKind: ListenKind? {
        get { listenKindRaw.flatMap { ListenKind(rawValue: $0) } }
        set { listenKindRaw = newValue?.rawValue }
    }

    var isCompleted: Bool { completedAt != nil }

    var sourceURL: URL? {
        guard let s = sourceURLString else { return nil }
        return URL(string: s)
    }

    var storedFileURL: URL? {
        guard let name = storedFileName else { return nil }
        return MediaStore.shared.url(for: name)
    }

    /// Best URL for media playback or reading: a user-owned filePath if
    /// present, otherwise a MediaStore-owned file (yt-dlp download, etc.).
    var playbackURL: URL? {
        if let p = filePath, !p.isEmpty {
            return URL(fileURLWithPath: p)
        }
        return storedFileURL
    }

    var thumbnailURL: URL? {
        guard let name = thumbnailFileName else { return nil }
        return MediaStore.shared.url(for: name)
    }
}

@Model
final class PodcastEpisode {
    @Attribute(.unique) var id: UUID
    var parent: TodoItem?
    var title: String
    var summary: String
    var publishedAt: Date?
    var audioURLString: String?
    var durationSeconds: Double?
    var playedAt: Date?
    var sortOrder: Double

    init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        publishedAt: Date? = nil,
        audioURLString: String? = nil,
        durationSeconds: Double? = nil,
        sortOrder: Double = 0
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.publishedAt = publishedAt
        self.audioURLString = audioURLString
        self.durationSeconds = durationSeconds
        self.sortOrder = sortOrder
    }

    var audioURL: URL? {
        guard let s = audioURLString else { return nil }
        return URL(string: s)
    }
}
