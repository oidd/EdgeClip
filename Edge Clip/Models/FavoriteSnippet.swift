import Foundation

enum FavoriteEntryOrderKey: Hashable {
    case snippet(UUID)
    case historyItem(UUID)

    init?(rawValue: String) {
        if rawValue.hasPrefix("snippet:"),
           let id = UUID(uuidString: String(rawValue.dropFirst("snippet:".count))) {
            self = .snippet(id)
            return
        }

        if rawValue.hasPrefix("history:"),
           let id = UUID(uuidString: String(rawValue.dropFirst("history:".count))) {
            self = .historyItem(id)
            return
        }

        return nil
    }

    var rawValue: String {
        switch self {
        case .snippet(let id):
            return "snippet:\(id.uuidString)"
        case .historyItem(let id):
            return "history:\(id.uuidString)"
        }
    }
}

struct FavoriteGroup: Identifiable, Codable, Equatable {
    static let maximumUserVisibleCharacterCount = 4
    static var defaultGeneratedName: String {
        AppLocalization.localized("未分组")
    }

    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int?
    var name: String
    var memberOrder: [String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int? = nil,
        name: String,
        memberOrder: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.name = name
        self.memberOrder = Self.sanitizedOrderTokens(memberOrder)
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isMeaningful: Bool {
        !trimmedName.isEmpty
    }

    static func clampedUserInputName(_ input: String) -> String {
        String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumUserVisibleCharacterCount))
    }

    mutating func prependSnippetID(_ snippetID: UUID) {
        prependMember(.snippet(snippetID))
    }

    mutating func prependHistoryItemID(_ itemID: UUID) {
        prependMember(.historyItem(itemID))
    }

    mutating func prependMember(_ member: FavoriteEntryOrderKey) {
        let rawValue = member.rawValue
        memberOrder.removeAll { $0 == rawValue }
        memberOrder.insert(rawValue, at: 0)
    }

    private static func sanitizedOrderTokens(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for token in tokens {
            guard FavoriteEntryOrderKey(rawValue: token) != nil else { continue }
            guard seen.insert(token).inserted else { continue }
            result.append(token)
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case sortOrder
        case name
        case memberOrder
        case snippetOrder
        case historyItemOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        if let storedMemberOrder = try container.decodeIfPresent([String].self, forKey: .memberOrder) {
            memberOrder = Self.sanitizedOrderTokens(storedMemberOrder)
        } else {
            let legacySnippetOrder = try container.decodeIfPresent([UUID].self, forKey: .snippetOrder) ?? []
            let legacyHistoryItemOrder = try container.decodeIfPresent([UUID].self, forKey: .historyItemOrder) ?? []
            let mergedLegacyOrder = legacySnippetOrder.map { FavoriteEntryOrderKey.snippet($0).rawValue } +
                legacyHistoryItemOrder.map { FavoriteEntryOrderKey.historyItem($0).rawValue }
            memberOrder = Self.sanitizedOrderTokens(mergedLegacyOrder)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try container.encode(name, forKey: .name)
        try container.encode(memberOrder, forKey: .memberOrder)
    }
}

struct FavoriteSnippet: Identifiable, Codable, Equatable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int?
    var text: String
    var sourceTextFingerprint: String?
    var groupIDs: [UUID]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int? = nil,
        text: String,
        sourceTextFingerprint: String? = nil,
        groupIDs: [UUID] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.text = text
        self.sourceTextFingerprint = sourceTextFingerprint
        self.groupIDs = Self.sanitizedGroupIDs(groupIDs)
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isMeaningful: Bool {
        !trimmedText.isEmpty
    }

    var contentFingerprint: String {
        ClipboardItem.contentFingerprint(for: text)
    }

    var title: String {
        let firstLine = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !firstLine.isEmpty {
            return String(firstLine.prefix(72))
        }

        let compact = trimmedText
        if !compact.isEmpty {
            return String(compact.prefix(72))
        }

        return AppLocalization.localized("未命名收藏")
    }

    var previewText: String {
        ClipboardItem.makePreviewText(from: text)
    }

    var detailLines: [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            return [AppLocalization.localized("空白文本")]
        }

        if normalized.count == 1 {
            return [String(normalized[0].prefix(160))]
        }

        return Array(normalized.prefix(2)).map { String($0.prefix(160)) }
    }

    var estimatedStorageBytes: Int {
        text.lengthOfBytes(using: .utf8) + 160
    }

    func belongs(to groupID: FavoriteGroup.ID?) -> Bool {
        guard let groupID else { return true }
        return groupIDs.contains(groupID)
    }

    func matchesSearchQuery(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }

        return title.localizedCaseInsensitiveContains(normalized) ||
            text.localizedCaseInsensitiveContains(normalized)
    }

    private static func sanitizedGroupIDs(_ groupIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for groupID in groupIDs where seen.insert(groupID).inserted {
            result.append(groupID)
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case sortOrder
        case text
        case sourceTextFingerprint
        case groupIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        sourceTextFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceTextFingerprint)
        groupIDs = Self.sanitizedGroupIDs(try container.decodeIfPresent([UUID].self, forKey: .groupIDs) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(sourceTextFingerprint, forKey: .sourceTextFingerprint)
        try container.encode(groupIDs, forKey: .groupIDs)
    }
}
