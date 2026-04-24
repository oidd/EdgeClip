import Foundation

enum FavoritePanelEntry: Identifiable, Equatable {
    case snippet(FavoriteSnippet)
    case historyItem(ClipboardItem)

    var id: UUID {
        switch self {
        case .snippet(let snippet):
            return snippet.id
        case .historyItem(let item):
            return item.id
        }
    }

    var snippet: FavoriteSnippet? {
        guard case .snippet(let snippet) = self else { return nil }
        return snippet
    }

    var historyItem: ClipboardItem? {
        guard case .historyItem(let item) = self else { return nil }
        return item
    }

    var orderKey: FavoriteEntryOrderKey {
        switch self {
        case .snippet(let snippet):
            return .snippet(snippet.id)
        case .historyItem(let item):
            return .historyItem(item.id)
        }
    }
}
