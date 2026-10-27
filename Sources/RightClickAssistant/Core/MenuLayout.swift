import Foundation

/// Finder 右键菜单展示模式。
/// - flat: 新建文件和实用工具固定使用子菜单，其他可用动作直接显示，收藏置顶。
/// - grouped: 兼容旧版，按动作分类放入二级子菜单。
public enum MenuLayoutMode: String, Codable, CaseIterable, Equatable, Identifiable {
    case flat
    case grouped

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .flat: return "直接显示"
        case .grouped: return "分类显示"
        }
    }
}

/// FinderSync 渲染前的菜单布局计划。
/// 这里刻意只保留 actionId 和标题，不依赖 AppKit，便于单测和复用。
public enum FinderMenuLayoutSection: Equatable {
    case directItems(actionIds: [String])
    case submenu(title: String, actionIds: [String])
    case separator
}

/// 把动作集合与用户配置转换成 renderer-neutral 菜单布局。
public enum FinderMenuLayoutBuilder {
    public static func build(
        actions: [MenuAction],
        mode: MenuLayoutMode,
        configuration: MenuConfiguration? = nil,
        isEnabled: (MenuAction) -> Bool,
        isFavorite: (MenuAction) -> Bool,
        isAvailable: (MenuAction) -> Bool
    ) -> [FinderMenuLayoutSection] {
        let eligible = actions.filter { action in
            isEnabled(action) && isAvailable(action)
        }

        if let configuration {
            let visible = Set(eligible.map(\.actionId))
            return configuration.normalized(actions: actions).entries.compactMap { entry in
                if let title = entry.title {
                    let ids = entry.actionIDs.filter { visible.contains($0) }
                    return ids.isEmpty ? nil : .submenu(title: title, actionIds: ids)
                }
                return visible.contains(entry.id) ? .directItems(actionIds: [entry.id]) : nil
            }
        }

        let newFileOrder: [SupportedFileType] = [.txt, .pages, .key, .numbers, .docx, .xlsx, .pptx, .md, .json, .csv, .html, .pdf]
        let newFiles = eligible.filter { $0.category == .newFile }.sorted {
            let left = ($0 as? NewFileAction).flatMap { newFileOrder.firstIndex(of: $0.fileType) } ?? Int.max
            let right = ($1 as? NewFileAction).flatMap { newFileOrder.firstIndex(of: $0.fileType) } ?? Int.max
            return left == right ? $0.actionId < $1.actionId : left < right
        }.map(\.actionId)
        let utilities = eligible.filter { $0.category == .utility }.sortedForMenu()
        let utilityIds = (utilities.filter(isFavorite) + utilities.filter { !isFavorite($0) }).map(\.actionId)
        let suffix: [FinderMenuLayoutSection] = utilityIds.isEmpty ? [] : [
            .submenu(title: "实用工具", actionIds: utilityIds)
        ]
        let remaining = eligible.filter { $0.category != .newFile && $0.category != .utility }
        let prefix: [FinderMenuLayoutSection] = newFiles.isEmpty ? [] : [
            .submenu(title: "新建文件", actionIds: newFiles)
        ]
        switch mode {
        case .flat:
            return prefix + buildFlatSections(
                actions: remaining,
                isFavorite: isFavorite
            ) + suffix
        case .grouped:
            return prefix + buildGroupedSections(
                actions: remaining,
                isFavorite: isFavorite
            ) + suffix
        }
    }

    private static func buildFlatSections(
        actions: [MenuAction],
        isFavorite: (MenuAction) -> Bool
    ) -> [FinderMenuLayoutSection] {
        let favoriteIds = actions
            .filter(isFavorite)
            .sortedForMenu()
            .map(\.actionId)

        let regularIds = ActionCategory.allCases.flatMap { category in
            actions
                .filter { $0.category == category && !isFavorite($0) }
                .sortedForMenu()
                .map(\.actionId)
        }

        let ids = favoriteIds + regularIds
        return ids.isEmpty ? [] : [.directItems(actionIds: ids)]
    }

    private static func buildGroupedSections(
        actions: [MenuAction],
        isFavorite: (MenuAction) -> Bool
    ) -> [FinderMenuLayoutSection] {
        var sections: [FinderMenuLayoutSection] = []

        let favoriteIds = actions
            .filter(isFavorite)
            .sortedForMenu()
            .map(\.actionId)
        if !favoriteIds.isEmpty {
            sections.append(.submenu(title: "常用", actionIds: favoriteIds))
        }

        for category in ActionCategory.allCases {
            let ids = actions
                .filter { $0.category == category && !isFavorite($0) }
                .sortedForMenu()
                .map(\.actionId)
            if !ids.isEmpty {
                sections.append(.submenu(title: category.localizedName, actionIds: ids))
            }
        }

        return sections
    }
}

private extension Array where Element == MenuAction {
    func sortedForMenu() -> [MenuAction] {
        sorted {
            if $0.localizedTitle == $1.localizedTitle {
                return $0.actionId < $1.actionId
            }
            return $0.localizedTitle < $1.localizedTitle
        }
    }
}
