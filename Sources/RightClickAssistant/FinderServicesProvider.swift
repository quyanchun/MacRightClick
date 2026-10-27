import AppKit
import Foundation

/// 为 iCloud Drive 等 File Provider 目录提供 FinderSync 之外的系统服务入口。
/// 面板仅展示核心层解析结果，用户确认后在宿主进程内提交给 ActionDispatcher。
final class FinderServicesProvider: NSObject {
    static let shared = FinderServicesProvider()

    private static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let fileURLType = NSPasteboard.PasteboardType("public.file-url")
    private static let forwardedActionType = NSPasteboard.PasteboardType(
        FinderQuickServiceProtocol.forwardedActionPasteboardType
    )

    @MainActor
    @objc(performFinderService:userData:error:)
    func performFinderService(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        AppLog.info("收到 Finder 服务请求：\(userData)", category: .host)
        let forwardedActionID = pasteboard.string(forType: Self.forwardedActionType)
        let request: FinderServiceRequest?
        if let forwardedActionID {
            let directActionIDs = Set(FinderQuickActionRuntime.currentItems().map(\.actionID))
            request = FinderServiceCatalog.request(
                userData: forwardedActionID,
                authorizedDirectActionIDs: directActionIDs
            )
        } else if FinderServiceCatalog.accepts(userData: userData) {
            request = .palette
        } else {
            request = nil
        }
        guard let request else {
            AppLog.error("拒绝未知或已过期的 Finder 服务请求：\(userData)", category: .host)
            errorPointer.pointee = "未知的右键助手服务" as NSString
            return
        }

        let paths = Self.selectionPaths(from: pasteboard)
        guard !paths.isEmpty else {
            AppLog.error("Finder 服务请求未包含有效文件路径：\(userData)", category: .host)
            errorPointer.pointee = "请先在 Finder 中选择文件或文件夹" as NSString
            return
        }

        if case let .directAction(actionID) = request {
            // Services can be invoked by any app. Require an explicit user gesture here.
            let alert = NSAlert()
            alert.messageText = "执行右键助手动作？"
            let title = ActionDispatcher.shared.action(forId: actionID)?.localizedTitle ?? actionID
            alert.informativeText = title + "\n" + paths.joined(separator: "\n")
            alert.addButton(withTitle: "取消")
            alert.addButton(withTitle: "执行")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            if let error = submissionError(actionID: actionID, paths: paths) {
                errorPointer.pointee = error as NSString
            } else {
                errorPointer.pointee = nil
            }
            return
        }

        let targetURLs = paths.map { URL(fileURLWithPath: $0) }
        let cache = ActionConfigCache.shared
        var favoriteRanks: [String: Int] = [:]
        for (rank, actionID) in SharedStorageManager.shared.favoriteActionIds.enumerated()
            where favoriteRanks[actionID] == nil {
            favoriteRanks[actionID] = rank
        }
        let items = FinderServiceCatalog.resolveItems(
            actions: ActionDispatcher.shared.allActions,
            targetURLs: targetURLs,
            isEnabled: {
                cache.isEnabled($0.actionId, default: $0.isEnabledByDefault)
            },
            isFavorite: { cache.isFavorite($0.actionId) },
            favoriteRank: { favoriteRanks[$0.actionId] }
        )
        guard !items.isEmpty else {
            errorPointer.pointee = "当前选中项没有已启用且可用的动作" as NSString
            return
        }

        errorPointer.pointee = nil
        FinderServicePaletteController.shared.show(
            items: items,
            selectedPaths: paths,
            onSelect: { [weak self] actionID in
                guard let self,
                      let error = self.submissionError(actionID: actionID, paths: paths) else {
                    return
                }
                self.showFailure(error)
            }
        )
    }

    @MainActor
    private func submissionError(actionID: String, paths: [String]) -> String? {
        let targetURLs = paths.map { URL(fileURLWithPath: $0) }
        guard let action = ActionDispatcher.shared.action(forId: actionID) else {
            return "动作已不存在，请重新打开右键助手"
        }

        let eligible = FinderServiceCatalog.resolveItems(
            actions: [action],
            targetURLs: targetURLs,
            isEnabled: { SharedStorageManager.shared.isActionEnabled($0) },
            isFavorite: { _ in false }
        )
        guard eligible.first?.actionID == actionID else {
            return "动作已关闭、目标已变化或当前不可用"
        }

        let submission = ActionDispatcher.shared.submit(
            actionId: actionID,
            targetURLs: targetURLs,
            invocationKind: .items,
            completion: { _ in }
        )
        return submission == .accepted ? nil : "无法提交操作"
    }

    private func showFailure(_ message: String) {
        SharedHUDManager.show(title: "操作未提交", content: message, isSuccess: false)
    }

    private static func selectionPaths(from pasteboard: NSPasteboard) -> [String] {
        let fileURLStrings = (pasteboard.pasteboardItems ?? []).compactMap {
            $0.string(forType: fileURLType)
        }
        let legacyPaths = pasteboard.propertyList(forType: legacyFilenamesType) as? [String] ?? []
        return FinderServiceCatalog.normalizedSelectionPaths(
            fileURLStrings: fileURLStrings,
            legacyPaths: legacyPaths
        )
    }
}
