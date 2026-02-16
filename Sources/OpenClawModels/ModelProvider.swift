import Foundation
import OpenClawCore
import OpenClawProtocol

/// Input payload passed to model providers.
public struct ModelGenerationRequest: Sendable, Equatable {
    /// Session key associated with generation request.
    public let sessionKey: String
    /// User prompt payload.
    public let prompt: String
    /// Optional system prompt prefix.
    public let systemPrompt: String?
    /// Optional explicit provider override.
    public let providerID: String?
    /// Additional provider-specific metadata.
    public let metadata: [String: String]

    /// Creates a model generation request.
    /// - Parameters:
    ///   - sessionKey: Session key.
    ///   - prompt: Prompt payload.
    ///   - systemPrompt: Optional system prompt.
    ///   - providerID: Optional provider override.
    ///   - metadata: Additional metadata.
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

/// Output payload returned from model providers.
public struct ModelGenerationResponse: Sendable, Equatable {
    /// Generated text output.
    public let text: String
    /// Provider identifier that generated the output.
    public let providerID: String
    /// Optional concrete model identifier.
    public let modelID: String?

    /// Creates a model generation response.
    /// - Parameters:
    ///   - text: Generated text output.
    ///   - providerID: Provider identifier.
    ///   - modelID: Optional concrete model identifier.
    public init(text: String, providerID: String, modelID: String? = nil) {
        self.text = text
        self.providerID = providerID
        self.modelID = modelID
    }
}

/// Interface implemented by model backends.
public protocol ModelProvider: Sendable {
    /// Stable provider identifier.
    var id: String { get }
    /// Executes generation request.
    /// - Parameter request: Generation request payload.
    /// - Returns: Generation response payload.
    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse
}

/// Default fallback provider returning deterministic placeholder output.
public struct EchoModelProvider: ModelProvider {
    /// Default echo provider identifier.
    public static let defaultID = "echo"
    /// Provider identifier.
    public let id: String

    /// Creates an echo provider.
    /// - Parameter id: Provider identifier.
    public init(id: String = EchoModelProvider.defaultID) {
        self.id = id
    }

    /// Returns a deterministic echo response.
    /// - Parameter request: Generation request payload.
    /// - Returns: Echo response.
    public func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
        _ = request
        return ModelGenerationResponse(text: "OK", providerID: self.id, modelID: "echo-1")
    }
}

/// Actor that resolves providers and routes generation requests.
public actor ModelRouter {
    private var providers: [String: any ModelProvider]
    private var defaultProviderID: String

    /// Creates a model router.
    /// - Parameters:
    ///   - defaultProviderID: Default provider identifier.
    ///   - providers: Initial provider list.
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

    /// Registers or replaces a provider.
    /// - Parameter provider: Provider implementation.
    public func register(_ provider: any ModelProvider) {
        self.providers[provider.id] = provider
    }

    /// Sets default provider by identifier.
    /// - Parameter id: Provider identifier.
    public func setDefaultProviderID(_ id: String) throws {
        guard self.providers[id] != nil else {
            throw OpenClawCoreError.invalidConfiguration("Unknown model provider: \(id)")
        }
        self.defaultProviderID = id
    }

    /// Returns configured provider identifiers sorted alphabetically.
    public func configuredProviderIDs() -> [String] {
        self.providers.keys.sorted()
    }

    /// Routes generation request to requested/default provider.
    /// - Parameter request: Generation request payload.
    /// - Returns: Provider response.
    public func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResponse {
        let requestedID = request.providerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackProvider = self.providers[self.defaultProviderID]
        guard let fallbackProvider else {
            throw OpenClawCoreError.invalidConfiguration("Default model provider is not registered")
        }

        if let requestedID, !requestedID.isEmpty, let provider = self.providers[requestedID] {
            return try await provider.generate(request)
        }

        return try await fallbackProvider.generate(request)
    }
}
