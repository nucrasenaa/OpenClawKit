import Foundation
import OpenClawCore

/// Actor that discovers, parses, and merges workspace skill definitions.
public actor SkillRegistry {
    private let workspaceRoot: URL
    private let extraSkillDirs: [URL]
    private let managedSkillsRoot: URL
    private let bundledSkillsRoot: URL?

    /// Creates a skill registry.
    /// - Parameters:
    ///   - workspaceRoot: Workspace root URL.
    ///   - extraSkillDirs: Optional extra search directories with highest precedence.
    ///   - managedSkillsRoot: Optional managed skill root override.
    ///   - bundledSkillsRoot: Optional bundled skill root override.
    public init(
        workspaceRoot: URL,
        extraSkillDirs: [URL] = [],
        managedSkillsRoot: URL? = nil,
        bundledSkillsRoot: URL? = nil
    ) {
        self.workspaceRoot = workspaceRoot
        self.extraSkillDirs = extraSkillDirs
        self.managedSkillsRoot = managedSkillsRoot ??
            OpenClawFileSystem.resolveHomeDirectory()
                .appendingPathComponent(".openclaw")
                .appendingPathComponent("skills")
        self.bundledSkillsRoot = bundledSkillsRoot
    }

    /// Loads and merges skills according to source precedence rules.
    /// - Returns: Sorted merged skill definitions.
    public func loadSkills() throws -> [SkillDefinition] {
        var merged: [String: SkillDefinition] = [:]

        for location in self.orderedLocations() {
            for skillFile in discoverSkillFiles(in: location.dir) {
                guard let definition = try parseSkill(fileURL: skillFile, source: location.source) else {
                    continue
                }
                merged[definition.name] = definition
            }
        }
        return merged.values.sorted { $0.name < $1.name }
    }

    /// Loads a prompt snapshot for model prompt assembly.
    /// - Returns: Prompt snapshot containing composed text and loaded skills.
    public func loadPromptSnapshot() throws -> SkillPromptSnapshot {
        let skills = try loadSkills()
        let promptEligible = skills.filter { !$0.invocation.disableModelInvocation }
        let prompt = buildPrompt(from: promptEligible)
        return SkillPromptSnapshot(prompt: prompt, skills: skills)
    }

    private func orderedLocations() -> [(source: SkillSource, dir: URL)] {
        let home = OpenClawFileSystem.resolveHomeDirectory()
        var list: [(SkillSource, URL)] = []
        list.append(contentsOf: self.extraSkillDirs.map { (.extra, $0) })
        if let bundledSkillsRoot {
            list.append((.bundled, bundledSkillsRoot))
        }
        list.append((.managed, self.managedSkillsRoot))
        list.append((.personalAgents, home.appendingPathComponent(".agents").appendingPathComponent("skills")))
        list.append((.projectAgents, self.workspaceRoot.appendingPathComponent(".agents").appendingPathComponent("skills")))
        list.append((.workspace, self.workspaceRoot.appendingPathComponent("skills")))
        return list
    }

    private func discoverSkillFiles(in root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }

        var files: [URL] = []
        let direct = root.appendingPathComponent("SKILL.md")
        if FileManager.default.fileExists(atPath: direct.path) {
            files.append(direct)
        }

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let skillFile = entry.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skillFile.path) {
                files.append(skillFile)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func parseSkill(fileURL: URL, source: SkillSource) throws -> SkillDefinition? {
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        let parsed = SkillFrontmatterParser.parse(raw)
        let name = parsed.frontmatter["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false) ? name! : fileURL.deletingLastPathComponent().lastPathComponent
        let description = parsed.frontmatter["description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !resolvedName.isEmpty else {
            return nil
        }
        return SkillDefinition(
            name: resolvedName,
            description: description,
            body: parsed.body.trimmingCharacters(in: .whitespacesAndNewlines),
            filePath: fileURL.path,
            source: source,
            frontmatter: parsed.frontmatter,
            metadata: SkillFrontmatterParser.resolveMetadata(from: parsed.frontmatter),
            invocation: SkillFrontmatterParser.resolveInvocationPolicy(from: parsed.frontmatter)
        )
    }

    private func buildPrompt(from skills: [SkillDefinition]) -> String {
        guard !skills.isEmpty else { return "" }
        var lines: [String] = ["## Skills"]
        for skill in skills.sorted(by: { $0.name < $1.name }) {
            lines.append("")
            lines.append("### \(skill.name)")
            if !skill.description.isEmpty {
                lines.append(skill.description)
            }
            if !skill.body.isEmpty {
                lines.append(skill.body)
            }
        }
        return lines.joined(separator: "\n")
    }
}
