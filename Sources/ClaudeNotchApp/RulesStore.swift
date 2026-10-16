import Foundation

public struct AllowRule: Codable, Equatable, Identifiable {
    public enum Scope: String, Codable {
        case tool                // the whole tool
        case toolWithCommand     // tool + command prefix
        case project             // cwd inside a folder
    }

    public var id: UUID
    public var scope: Scope
    public var value: String
    public var label: String     // description shown to the user
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        scope: Scope,
        value: String,
        label: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.value = value
        self.label = label
        self.createdAt = createdAt
    }

    public func matches(_ event: HookEvent) -> Bool {
        switch scope {
        case .tool:
            return event.toolName == value
        case .toolWithCommand:
            // value: "Bash:ls"
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return false }
            let tool = parts[0]
            let prefix = parts[1]
            guard event.toolName == tool else { return false }
            let cmd = event.commandPreview.trimmingCharacters(in: .whitespacesAndNewlines)
            return cmd.hasPrefix(prefix)
        case .project:
            return event.cwd.hasPrefix(value)
        }
    }
}

public final class RulesStore: ObservableObject {
    @Published public private(set) var rules: [AllowRule] = []
    private let path: String

    public init(path: String = Paths.rules) {
        self.path = path
        load()
    }

    public func load() {
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            rules = []
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            rules = try decoder.decode([AllowRule].self, from: data)
        } catch {
            Logger.shared.warn("load rules failed: \(error)")
            rules = []
        }
    }

    public func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(rules)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            Logger.shared.error("save rules failed: \(error)")
        }
    }

    public func add(_ rule: AllowRule) {
        DispatchQueue.main.async {
            self.rules.append(rule)
            self.save()
        }
    }

    public func remove(id: UUID) {
        DispatchQueue.main.async {
            self.rules.removeAll { $0.id == id }
            self.save()
        }
    }

    public func matches(_ event: HookEvent) -> Bool {
        return rules.contains { $0.matches(event) }
    }
}

