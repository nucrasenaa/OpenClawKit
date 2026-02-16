import Foundation

public enum SkillSource: String, Codable, Sendable {
    case extra
    case bundled
    case managed
    case personalAgents
    case projectAgents
    case workspace
}

public struct SkillMetadata: Codable, Sendable, Equatable {
    public var always: Bool?
    public var skillKey: String?
    public var primaryEnv: String?

    public init(always: Bool? = nil, skillKey: String? = nil, primaryEnv: String? = nil) {
        self.always = always
        self.skillKey = skillKey
        self.primaryEnv = primaryEnv
    }
}

public struct SkillInvocationPolicy: Codable, Sendable, Equatable {
    public var userInvocable: Bool
    public var disableModelInvocation: Bool

    public init(userInvocable: Bool = true, disableModelInvocation: Bool = false) {
        self.userInvocable = userInvocable
        self.disableModelInvocation = disableModelInvocation
    }
}

public struct SkillDefinition: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let body: String
    public let filePath: String
    public let source: SkillSource
    public let frontmatter: [String: String]
    public let metadata: SkillMetadata
    public let invocation: SkillInvocationPolicy

    public init(
        name: String,
        description: String,
        body: String,
        filePath: String,
        source: SkillSource,
        frontmatter: [String: String] = [:],
        metadata: SkillMetadata = SkillMetadata(),
        invocation: SkillInvocationPolicy = SkillInvocationPolicy()
    ) {
        self.name = name
        self.description = description
        self.body = body
        self.filePath = filePath
        self.source = source
        self.frontmatter = frontmatter
        self.metadata = metadata
        self.invocation = invocation
    }
}

public struct SkillPromptSnapshot: Sendable, Equatable {
    public let prompt: String
    public let skills: [SkillDefinition]

    public init(prompt: String, skills: [SkillDefinition]) {
        self.prompt = prompt
        self.skills = skills
    }
}
