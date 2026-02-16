import Foundation

enum SkillFrontmatterParser {
    static func parse(_ content: String) -> (frontmatter: [String: String], body: String) {
        var frontmatter: [String: String] = [:]
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return (frontmatter, content)
        }

        var endIndex: Int?
        var idx = 1
        while idx < lines.count {
            let line = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" {
                endIndex = idx
                break
            }
            if let sep = line.firstIndex(of: ":") {
                let key = String(line[..<sep]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawValue = String(line[line.index(after: sep)...])
                let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !key.isEmpty {
                    frontmatter[key] = value
                }
            }
            idx += 1
        }

        guard let endIndex else {
            return (frontmatter, content)
        }
        let bodyLines = lines[(endIndex + 1)...]
        return (frontmatter, bodyLines.joined(separator: "\n"))
    }

    static func resolveMetadata(from frontmatter: [String: String]) -> SkillMetadata {
        SkillMetadata(
            always: parseBool(frontmatter["always"] ?? frontmatter["openclaw.always"]),
            skillKey: frontmatter["skillKey"] ?? frontmatter["openclaw.skillKey"],
            primaryEnv: frontmatter["primaryEnv"] ?? frontmatter["openclaw.primaryEnv"]
        )
    }

    static func resolveInvocationPolicy(from frontmatter: [String: String]) -> SkillInvocationPolicy {
        SkillInvocationPolicy(
            userInvocable: parseBool(frontmatter["user-invocable"], defaultValue: true) ?? true,
            disableModelInvocation: parseBool(
                frontmatter["disable-model-invocation"],
                defaultValue: false
            ) ?? false
        )
    }

    private static func parseBool(_ value: String?, defaultValue: Bool? = nil) -> Bool? {
        guard let value else { return defaultValue }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }
}
