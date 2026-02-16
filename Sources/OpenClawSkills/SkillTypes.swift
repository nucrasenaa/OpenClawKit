import Foundation

/// Source precedence buckets for discovered skills.
public enum SkillSource: String, Codable, Sendable {
    case extra
    case bundled
    case managed
    case personalAgents
    case projectAgents
    case workspace
}

/// Parsed skill metadata fields.
public struct SkillMetadata: Codable, Sendable, Equatable {
    /// Marks skill as always-active in prompt assembly.
    public var always: Bool?
    /// Optional unique skill key.
    public var skillKey: String?
    /// Optional primary environment hint.
    public var primaryEnv: String?

    /// Creates skill metadata.
    /// - Parameters:
    ///   - always: Whether skill is always active.
    ///   - skillKey: Optional skill key.
    ///   - primaryEnv: Optional environment hint.
    public init(always: Bool? = nil, skillKey: String? = nil, primaryEnv: String? = nil) {
        self.always = always
        self.skillKey = skillKey
        self.primaryEnv = primaryEnv
    }
}

/// Invocation policy flags parsed from skill frontmatter.
public struct SkillInvocationPolicy: Codable, Sendable, Equatable {
    /// Whether users may explicitly invoke the skill.
    public var userInvocable: Bool
    /// Whether skill should be excluded from model prompt injection.
    public var disableModelInvocation: Bool

    /// Creates invocation policy flags.
    /// - Parameters:
    ///   - userInvocable: Whether users can invoke the skill.
    ///   - disableModelInvocation: Whether to exclude from model prompt assembly.
    public init(userInvocable: Bool = true, disableModelInvocation: Bool = false) {
        self.userInvocable = userInvocable
        self.disableModelInvocation = disableModelInvocation
    }
}

/// Fully parsed skill definition.
public struct SkillDefinition: Codable, Sendable, Equatable {
    /// Skill name.
    public let name: String
    /// Human-readable skill description.
    public let description: String
    /// Skill body/instructions.
    public let body: String
    /// Source file path.
    public let filePath: String
    /// Discovery source bucket.
    public let source: SkillSource
    /// Raw parsed frontmatter map.
    public let frontmatter: [String: String]
    /// Normalized metadata payload.
    public let metadata: SkillMetadata
    /// Invocation policy flags.
    public let invocation: SkillInvocationPolicy

    /// Creates a skill definition.
    /// - Parameters:
    ///   - name: Skill name.
    ///   - description: Human-readable description.
    ///   - body: Skill body/instructions.
    ///   - filePath: Source file path.
    ///   - source: Discovery source bucket.
    ///   - frontmatter: Raw parsed frontmatter.
    ///   - metadata: Normalized metadata payload.
    ///   - invocation: Invocation policy flags.
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

/// Snapshot containing composed skill prompt text and source skills.
public struct SkillPromptSnapshot: Sendable, Equatable {
    /// Composed prompt text to inject into model requests.
    public let prompt: String
    /// Loaded skills used to produce prompt.
    public let skills: [SkillDefinition]

    /// Creates a prompt snapshot.
    /// - Parameters:
    ///   - prompt: Composed prompt text.
    ///   - skills: Loaded skills.
    public init(prompt: String, skills: [SkillDefinition]) {
        self.prompt = prompt
        self.skills = skills
    }
}
