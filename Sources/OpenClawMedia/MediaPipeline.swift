import Foundation
import OpenClawCore

public enum MediaKind: String, Sendable {
    case image
    case audio
    case video
    case document
    case unknown
}

public struct MediaBlob: Sendable, Equatable {
    public let id: UUID
    public let mimeType: String
    public let data: Data

    public init(id: UUID = UUID(), mimeType: String, data: Data) {
        self.id = id
        self.mimeType = mimeType
        self.data = data
    }
}

public actor MediaPipeline {
    private let maxBytes: Int

    public init(maxBytes: Int = 10 * 1024 * 1024) {
        self.maxBytes = max(1024, maxBytes)
    }

    public func normalize(_ blob: MediaBlob) async throws -> MediaBlob {
        guard !blob.mimeType.isEmpty else {
            throw OpenClawCoreError.invalidConfiguration("mimeType must not be empty")
        }
        guard blob.data.count <= self.maxBytes else {
            throw OpenClawCoreError.unavailable("Media blob exceeds maximum supported size")
        }
        return blob
    }

    public func kind(for mimeType: String) -> MediaKind {
        let normalized = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("image/") { return .image }
        if normalized.hasPrefix("audio/") { return .audio }
        if normalized.hasPrefix("video/") { return .video }
        if normalized.hasPrefix("application/") || normalized.hasPrefix("text/") { return .document }
        return .unknown
    }
}

