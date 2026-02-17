import Foundation
import OpenClawCore

/// Result payload from a matched skill invocation.
public struct SkillInvocationResult: Sendable, Equatable {
    /// Invoked skill name.
    public let skillName: String
    /// Raw skill output payload.
    public let output: String

    /// Creates a skill invocation result.
    /// - Parameters:
    ///   - skillName: Invoked skill name.
    ///   - output: Raw output text.
    public init(skillName: String, output: String) {
        self.skillName = skillName
        self.output = output
    }
}

/// Resolves and executes workspace skills for inbound user messages.
public actor SkillInvocationEngine {
    private struct InvocationMatch: Sendable {
        let skill: SkillDefinition
        let input: String
        let explicitCommand: Bool
    }

    private let workspaceRoot: URL
    private let registry: SkillRegistry
    private let processRunner: ProcessRunner
    private let jsExecutor: JSSkillExecutor?

    /// Creates a skill invocation engine.
    /// - Parameters:
    ///   - workspaceRoot: Workspace root that contains skills.
    ///   - processRunner: Process execution runtime for non-JS entrypoints.
    public init(workspaceRoot: URL, processRunner: ProcessRunner = ProcessRunner()) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.registry = SkillRegistry(workspaceRoot: self.workspaceRoot)
        self.processRunner = processRunner
        self.jsExecutor = try? JSSkillExecutor(workspaceRoot: self.workspaceRoot)
    }

    /// Attempts to resolve and execute a skill from a user message.
    ///
    /// Supported invocation styles:
    /// - `/skill <name> [args]`
    /// - `/<name> [args]`
    /// - Natural-language references to discovered skill names.
    ///
    /// - Parameter message: Raw inbound message text.
    /// - Returns: Invocation result, or `nil` when no skill applies.
    public func invokeIfRequested(message: String) async throws -> SkillInvocationResult? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let skills = try await self.registry.loadSkills()
            .filter { $0.invocation.userInvocable }
        guard !skills.isEmpty else {
            return nil
        }

        if let explicit = self.resolveExplicitInvocation(from: trimmed, skills: skills) {
            return try await self.execute(match: explicit)
        }
        if let inferred = self.resolveInferredInvocation(from: trimmed, skills: skills) {
            do {
                return try await self.execute(match: inferred)
            } catch {
                // Avoid failing the full response for best-effort implicit invocation.
                return nil
            }
        }
        return nil
    }

    private func resolveExplicitInvocation(
        from message: String,
        skills: [SkillDefinition]
    ) -> InvocationMatch? {
        guard message.hasPrefix("/") else {
            return nil
        }
        let parts = message.split(
            maxSplits: 2,
            omittingEmptySubsequences: true,
            whereSeparator: \.isWhitespace
        )
        guard let head = parts.first else {
            return nil
        }

        let command = String(head.dropFirst())
        guard !command.isEmpty else {
            return nil
        }

        var requestedSkillName = command
        var rawArgs: String = ""

        if command.caseInsensitiveCompare("skill") == .orderedSame {
            guard parts.count >= 2 else {
                return nil
            }
            requestedSkillName = String(parts[1])
            if parts.count >= 3 {
                rawArgs = String(parts[2])
            }
        } else if parts.count >= 2 {
            rawArgs = String(parts[1])
            if parts.count >= 3 {
                rawArgs += " " + String(parts[2])
            }
        }

        guard let skill = self.resolveSkill(named: requestedSkillName, in: skills) else {
            return nil
        }
        let normalizedInput = Self.normalizeExplicitInput(rawArgs)
        return InvocationMatch(skill: skill, input: normalizedInput, explicitCommand: true)
    }

    private func resolveInferredInvocation(
        from message: String,
        skills: [SkillDefinition]
    ) -> InvocationMatch? {
        let normalizedMessage = Self.normalizedNaturalLanguage(message)
        guard !normalizedMessage.isEmpty else {
            return nil
        }

        let sortedSkills = skills.sorted {
            Self.normalizedNaturalLanguage($0.name).count > Self.normalizedNaturalLanguage($1.name).count
        }

        for skill in sortedSkills {
            let token = Self.normalizedNaturalLanguage(skill.name)
            guard !token.isEmpty else {
                continue
            }
            if Self.message(normalizedMessage, containsSkillToken: token) {
                return InvocationMatch(skill: skill, input: message, explicitCommand: false)
            }
        }
        return nil
    }

    private func resolveSkill(named name: String, in skills: [SkillDefinition]) -> SkillDefinition? {
        let lookup = Self.normalizedSkillLookup(name)
        return skills.first { Self.normalizedSkillLookup($0.name) == lookup }
    }

    private func execute(match: InvocationMatch) async throws -> SkillInvocationResult {
        guard let entrypoint = try await self.registry.resolveEntrypoint(for: match.skill) else {
            throw OpenClawCoreError.invalidConfiguration(
                "Skill '\(match.skill.name)' is missing an entrypoint"
            )
        }
        let output = try await self.executeEntrypoint(
            skill: match.skill,
            entrypoint: entrypoint,
            input: match.input
        )
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutput.isEmpty && match.explicitCommand {
            throw OpenClawCoreError.unavailable("Skill '\(match.skill.name)' returned no output")
        }
        return SkillInvocationResult(skillName: match.skill.name, output: trimmedOutput)
    }

    private func executeEntrypoint(
        skill: SkillDefinition,
        entrypoint: URL,
        input: String
    ) async throws -> String {
        let ext = entrypoint.pathExtension.lowercased()
        let primaryEnv = (skill.metadata.primaryEnv ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if Self.isJavaScriptEntrypoint(extension: ext, primaryEnv: primaryEnv),
           let jsExecutor = self.jsExecutor
        {
            let relativePath = try self.relativePathToWorkspace(entrypoint)
            let result = try await jsExecutor.executeFile(scriptPath: relativePath, input: input)
            let trimmedOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedOutput.isEmpty {
                return trimmedOutput
            }
            return result.logs.last ?? ""
        }

        let command = self.buildProcessCommand(
            entrypoint: entrypoint,
            pathExtension: ext,
            primaryEnv: primaryEnv,
            input: input
        )
        let result = try await self.processRunner.run(
            command,
            cwd: entrypoint.deletingLastPathComponent()
        )
        if result.exitCode != 0 {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw OpenClawCoreError.unavailable(
                "Skill '\(skill.name)' failed with exit code \(result.exitCode): \(message)"
            )
        }
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines) : stdout
    }

    private func relativePathToWorkspace(_ absolutePath: URL) throws -> String {
        let workspacePath = self.workspaceRoot.standardizedFileURL.path
        let targetPath = absolutePath.standardizedFileURL.path
        let prefix = workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/"
        guard targetPath.hasPrefix(prefix) else {
            throw OpenClawCoreError.invalidConfiguration("Skill entrypoint must stay within workspace root")
        }
        return String(targetPath.dropFirst(prefix.count))
    }

    private func buildProcessCommand(
        entrypoint: URL,
        pathExtension: String,
        primaryEnv: String,
        input: String
    ) -> [String] {
        var command: [String]
        if !primaryEnv.isEmpty {
            let normalizedPrimaryEnv: String
            switch primaryEnv {
            case "js", "javascript", "javascriptcore":
                normalizedPrimaryEnv = "node"
            default:
                normalizedPrimaryEnv = primaryEnv
            }
            let envParts = normalizedPrimaryEnv
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            command = ["/usr/bin/env"] + envParts + [entrypoint.path]
        } else {
            switch pathExtension {
            case "py":
                command = ["/usr/bin/env", "python3", entrypoint.path]
            case "sh":
                command = ["/usr/bin/env", "sh", entrypoint.path]
            case "js", "mjs", "cjs":
                command = ["/usr/bin/env", "node", entrypoint.path]
            default:
                command = [entrypoint.path]
            }
        }

        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInput.isEmpty {
            command.append(trimmedInput)
        }
        return command
    }

    private static func isJavaScriptEntrypoint(extension pathExtension: String, primaryEnv: String) -> Bool {
        if pathExtension == "js" || pathExtension == "mjs" || pathExtension == "cjs" {
            return true
        }
        return primaryEnv == "js" || primaryEnv == "javascript" || primaryEnv == "javascriptcore"
    }

    private static func normalizedSkillLookup(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[\\s_]+", with: "-", options: .regularExpression)
    }

    private static func normalizedNaturalLanguage(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func message(_ normalizedMessage: String, containsSkillToken token: String) -> Bool {
        let paddedMessage = " " + normalizedMessage + " "
        let paddedToken = " " + token + " "
        return paddedMessage.contains(paddedToken)
    }

    private static func normalizeExplicitInput(_ rawArgs: String) -> String {
        rawArgs.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
