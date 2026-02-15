import Foundation
import OpenClawCore

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
    public init() {}

    public func normalize(_ blob: MediaBlob) async throws -> MediaBlob {
        guard !blob.mimeType.isEmpty else {
            throw OpenClawCoreError.invalidConfiguration("mimeType must not be empty")
        }
        return blob
    }
}

