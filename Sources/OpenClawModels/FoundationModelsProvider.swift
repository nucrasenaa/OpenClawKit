import Foundation
import OpenClawCore

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct FoundationModelsProvider: ModelProvider {
    public static let providerID = "foundation"
    public let id: String

    public init(id: String = FoundationModelsProvider.providerID) {
        self.id = id
    }

    public func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            let session = LanguageModelSession()
            let response = try await session.respond(to: request.prompt)
            return ModelGenerationResponse(
                text: String(describing: response),
                providerID: self.id,
                modelID: "apple-foundation-default"
            )
        }
        throw OpenClawCoreError.unavailable("Foundation Models require Apple OS 26+")
        #else
        _ = request
        throw OpenClawCoreError.unavailable("Foundation Models framework is unavailable on this platform")
        #endif
    }
}
