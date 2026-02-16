import Foundation
import OpenClawCore
import OpenClawProtocol

public struct ModelGenerationRequest: Sendable, Equatable {
    public let sessionKey: String
    public let prompt: String
    public let systemPrompt: String?
    public let providerID: String?
    public let metadata: [String: String]

    public init(
        sessionKey: String,
        prompt: String,
        systemPrompt: String? = nil,
        providerID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.sessionKey = sessionKey
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.metadata = metadata
    }
}

public struct ModelGenerationResponse: Sendable, Equatable {
    public let text: String
    public let providerID: String
    public let modelID: String?

    public init(text: String, providerID: String, modelID: String? = nil) {
        self.text = text
        self.providerID = providerID
        self.modelID = modelID
    }
}

public protocol ModelProvider: Sendable {
    var id: String { get }
    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse
}

public struct EchoModelProvider: ModelProvider {
    public static let defaultID = "echo"
    public let id: String

    public init(id: String = EchoModelProvider.defaultID) {
        self.id = id
    }

    public func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
        _ = request
        return ModelGenerationResponse(text: "OK", providerID: self.id, modelID: "echo-1")
    }
}

public actor ModelRouter {
    private var providers: [String: any ModelProvider]
    private var defaultProviderID: String

    public init(
        defaultProviderID: String = EchoModelProvider.defaultID,
        providers: [any ModelProvider] = [EchoModelProvider()]
    ) {
        var map: [String: any ModelProvider] = [:]
        for provider in providers {
            map[provider.id] = provider
        }
        if map[defaultProviderID] == nil {
            map[EchoModelProvider.defaultID] = EchoModelProvider()
            self.defaultProviderID = EchoModelProvider.defaultID
        } else {
            self.defaultProviderID = defaultProviderID
        }
        self.providers = map
    }

    public func register(_ provider: any ModelProvider) {
        self.providers[provider.id] = provider
    }

    public func setDefaultProviderID(_ id: String) throws {
        guard self.providers[id] != nil else {
            throw OpenClawCoreError.invalidConfiguration("Unknown model provider: \(id)")
        }
        self.defaultProviderID = id
    }

    public func configuredProviderIDs() -> [String] {
        self.providers.keys.sorted()
    }

    public func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
        let requestedID = request.providerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedID = (requestedID?.isEmpty == false) ? requestedID! : self.defaultProviderID
        guard let provider = self.providers[resolvedID] else {
            throw OpenClawCoreError.unavailable("No model provider registered for \(resolvedID)")
        }
        return try await provider.generate(request)
    }
}
