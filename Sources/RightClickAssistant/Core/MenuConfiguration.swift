import Foundation

/// A root entry is either an action or a group of action IDs. Groups cannot contain groups.
public struct MenuEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String?
    public var actionIDs: [String]
    public var isGroup: Bool { title != nil }

    public static func action(_ id: String) -> MenuEntry { MenuEntry(id: id, title: nil, actionIDs: []) }
    public static func group(_ title: String, actions: [String] = []) -> MenuEntry {
        MenuEntry(id: "group.\(UUID().uuidString)", title: title, actionIDs: actions)
    }
}

public struct MenuConfiguration: Codable, Equatable, Sendable {
    public var entries: [MenuEntry]
    public init(entries: [MenuEntry]) { self.entries = entries }

    public static func initial(actions: [MenuAction], mode: MenuLayoutMode, favorites: Set<String>) -> Self {
        let sections = FinderMenuLayoutBuilder.build(actions: actions, mode: mode,
            isEnabled: { _ in true }, isFavorite: { favorites.contains($0.actionId) }, isAvailable: { _ in true })
        return Self(entries: sections.flatMap { section -> [MenuEntry] in
            switch section {
            case .directItems(let ids): return ids.map(MenuEntry.action)
            case .submenu(let title, let ids): return [.group(title, actions: ids)]
            case .separator: return []
            }
        })
    }

    /// Keep each known action exactly once, including disabled actions, so toggling never loses placement.
    public func normalized(actions: [MenuAction]) -> Self {
        let known = Set(actions.map(\.actionId))
        var seen = Set<String>()
        var groups = Set<String>()
        var result: [MenuEntry] = []
        for var entry in entries {
            if entry.isGroup {
                guard !known.contains(entry.id), groups.insert(entry.id).inserted else { continue }
                entry.title = String((entry.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                if entry.title?.isEmpty != false { entry.title = "分组" }
                entry.actionIDs = entry.actionIDs.filter { known.contains($0) && seen.insert($0).inserted }
                result.append(entry)
            } else if known.contains(entry.id), seen.insert(entry.id).inserted {
                result.append(.action(entry.id))
            }
        }
        // New actions introduced by later versions remain accessible without resetting existing positions.
        for action in actions.sorted(by: { $0.actionId < $1.actionId }) where !seen.contains(action.actionId) {
            if let index = result.firstIndex(where: { $0.title == action.category.localizedName }) {
                result[index].actionIDs.append(action.actionId)
            } else {
                result.append(.action(action.actionId))
            }
        }
        return Self(entries: result)
    }

    @discardableResult
    public mutating func move(_ itemID: String, toGroup groupID: String? = nil, before targetID: String? = nil) -> Bool {
        guard itemID != targetID else { return false }
        let rootEntry = entries.first { $0.id == itemID }
        let isGroup = rootEntry?.isGroup == true
        guard rootEntry != nil || entries.contains(where: { $0.actionIDs.contains(itemID) }) else { return false }
        if let groupID {
            guard !isGroup, let group = entries.first(where: { $0.id == groupID && $0.isGroup }),
                  targetID == nil || group.actionIDs.contains(targetID!) else { return false }
        } else if let targetID, !entries.contains(where: { $0.id == targetID }) { return false }
        let moving = rootEntry ?? .action(itemID)
        entries.removeAll { $0.id == itemID }
        for index in entries.indices { entries[index].actionIDs.removeAll { $0 == itemID } }
        if let groupID, let index = entries.firstIndex(where: { $0.id == groupID }) {
            let position = targetID.flatMap { entries[index].actionIDs.firstIndex(of: $0) } ?? entries[index].actionIDs.count
            entries[index].actionIDs.insert(itemID, at: position)
        } else {
            let position = targetID.flatMap { id in entries.firstIndex { $0.id == id } } ?? entries.count
            entries.insert(moving, at: position)
        }
        return true
    }

    public mutating func nudge(_ itemID: String, by offset: Int) {
        if let index = entries.firstIndex(where: { $0.id == itemID }) {
            let target = index + offset
            guard entries.indices.contains(target) else { return }
            entries.swapAt(index, target)
        } else if let group = entries.firstIndex(where: { $0.actionIDs.contains(itemID) }),
                  let index = entries[group].actionIDs.firstIndex(of: itemID) {
            let target = index + offset
            guard entries[group].actionIDs.indices.contains(target) else { return }
            entries[group].actionIDs.swapAt(index, target)
        }
    }

    public mutating func removeGroup(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.isGroup }) else { return }
        let children = entries.remove(at: index).actionIDs.map(MenuEntry.action)
        entries.insert(contentsOf: children, at: index)
    }
}
