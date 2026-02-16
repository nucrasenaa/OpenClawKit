import Foundation
import OpenClawCore

/// Normalized media categories.
public enum MediaKind: String, Sendable {
    case image
    case audio
    case video
    case document
    case unknown
}

/// Raw media payload passed through the media pipeline.
public struct MediaBlob: Sendable, Equatable {
    /// Blob identifier.
    public let id: UUID
    /// MIME type label.
    public let mimeType: String
    /// Raw media bytes.
    public let data: Data

    /// Creates a media blob.
    /// - Parameters:
    ///   - id: Blob identifier.
    ///   - mimeType: MIME type label.
    ///   - data: Raw media bytes.
    public init(id: UUID = UUID(), mimeType: String, data: Data) {
        self.id = id
        self.mimeType = mimeType
        self.data = data
    }
}

/// Actor-backed media normalizer and classifier.
public actor MediaPipeline {
    private let maxBytes: Int

    /// Creates a media pipeline.
    /// - Parameter maxBytes: Maximum allowed blob size.
    public init(maxBytes: Int = 10 * 1024 * 1024) {
        self.maxBytes = max(1024, maxBytes)
    }

    /// Validates and normalizes a media blob.
    /// - Parameter blob: Media blob to normalize.
    /// - Returns: Unmodified blob when valid.
    public func normalize(_ blob: MediaBlob) async throws -> MediaBlob {
        guard !blob.mimeType.isEmpty else {
            throw OpenClawCoreError.invalidConfiguration("mimeType must not be empty")
        }
        guard blob.data.count <= self.maxBytes else {
            throw OpenClawCoreError.unavailable("Media blob exceeds maximum supported size")
        }
        return blob
    }

    /// Classifies a MIME type into a normalized media category.
    /// - Parameter mimeType: MIME type string.
    /// - Returns: Detected media kind.
    public func kind(for mimeType: String) -> MediaKind {
        let normalized = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("image/") { return .image }
        if normalized.hasPrefix("audio/") { return .audio }
        if normalized.hasPrefix("video/") { return .video }
        if normalized.hasPrefix("application/") || normalized.hasPrefix("text/") { return .document }
        return .unknown
    }
}

