import Foundation
import AppKit

/// 支持的终端或编辑器类型
public enum TerminalEditorType: String, Codable, CaseIterable, Sendable {
    case terminal = "terminal"
    case iterm2 = "iterm2"
    case warp = "warp"
    case vscode = "vscode"
    case sublime = "sublime"
    case cursor = "cursor"
    case workbuddy = "workbuddy"
    case codex = "codex"
    
    public var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm2: return "com.googlecode.iterm2"
        case .warp: return "dev.warp.Warp-Stable"
        case .vscode: return "com.microsoft.VSCode"
        case .sublime: return "com.sublimetext.4" // 注册表兼容 Sublime Text 3
        case .cursor: return "com.todesktop.230313mptvbe7of" // Cursor's custom bundle ID
        case .workbuddy: return "com.tencent.workbuddy.mac"
        case .codex: return "com.openai.codex"
        }
    }
    
    public var displayName: String {
        switch self {
        case .terminal: return "系统终端 (Terminal)"
        case .iterm2: return "iTerm2"
        case .warp: return "Warp 终端"
        case .vscode: return "Visual Studio Code"
        case .sublime: return "Sublime Text"
        case .cursor: return "Cursor"
        case .workbuddy: return "WorkBuddy"
        case .codex: return "Codex"
        }
    }
}

public final class TerminalOpenAction: MenuAction, @unchecked Sendable {
    public let actionId: String
    public let localizedTitle: String
    public let iconName: String?
    public let category: ActionCategory = .terminal
    
    public let appType: TerminalEditorType
    
    public var associatedBundleIdentifier: String? {
        return appType.bundleIdentifier
    }

    public var tier: ActionTier {
        return appType == .terminal ? .essential : .professional
    }

    public var isEnabledByDefault: Bool {
        return tier == .essential || appType == .workbuddy || appType == .codex
    }
    
    public init(type: TerminalEditorType) {
        self.appType = type
        self.actionId = "guyue.action.terminal.\(type.rawValue)"
        self.localizedTitle = "在 \(type.displayName) 中打开"
        
        switch type {
        case .terminal: self.iconName = "terminal"
        case .iterm2: self.iconName = "terminal.fill"
        case .warp: self.iconName = "terminal.fill"
        case .vscode: self.iconName = "chevron.left.forwardslash.chevron.right"
        case .sublime: self.iconName = "doc.plaintext"
        case .cursor: self.iconName = "sparkles"
        case .workbuddy: self.iconName = "sparkles"
        case .codex: self.iconName = "sparkles"
        }
    }
    
    public func isAvailable(for targetURLs: [URL]) -> Bool {
        // 只有当安装了对应的软件，此右键菜单项才应该被启用并显示给用户。
        // 走进程内缓存，避免 menu(for:) 渲染时重复触发 Launch Services 同步查询。
        guard InstalledAppRegistry.shared.isInstalled(appType.bundleIdentifier) else {
            return false
        }
        return appType == .workbuddy || appType == .codex ? !urlsToOpen(for: targetURLs).isEmpty : !targetURLs.isEmpty
    }
    
    public func execute(targetURLs: [URL]) -> Bool {
        return submit(targetURLs: targetURLs, completion: { _ in }) == .accepted
    }

    public func submit(
        targetURLs: [URL],
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) -> ActionSubmission {
        let openingURLs = urlsToOpen(for: targetURLs)
        guard !openingURLs.isEmpty else {
            completion(.failed)
            return .rejected
        }
        
        // 编辑器接收原始选中项；终端接收工作目录。通过文件 URL 传递，避免 shell 转义和参数解析。
        guard let appURL = InstalledAppRegistry.shared.url(for: appType.bundleIdentifier) else {
            AppLog.error("找不到应用: \(self.appType.displayName)", category: .action)
            completion(.failed)
            return .rejected
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        if appType == .terminal || appType == .iterm2 || appType == .warp {
            configuration.arguments = openingURLs.map(\.path)
        }
        
        
        // 异步拉起目标应用，避免 DispatchGroup.wait() 阻塞调用线程（尤其是主线程）导致 UI 卡死。
        // NSWorkspace.open 回调在后台队列执行，HUD 展示内部已切换到主线程。
        NSWorkspace.shared.open(openingURLs, withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error = error {
                print("[TerminalAction] 拉起 \(self.appType.displayName) 失败: \(error.localizedDescription)")
                SharedHUDManager.show(
                    title: "拉起失败",
                    content: "无法启动 \(self.appType.displayName)",
                    isSuccess: false
                )
                completion(.failed)
            } else {
                SharedHUDManager.show(
                    title: "拉起成功",
                    content: "已在 \(self.appType.displayName) 中打开所选项目",
                    isSuccess: true
                )
                completion(.succeeded)
            }
        }
        
        // 立即返回，不等待异步结果。HUD 会在回调中展示成功/失败。
        // 调用方 ActionDispatcher 不依赖返回值做关键路径决策。
        return .accepted
    }
    
    func urlsToOpen(for targetURLs: [URL]) -> [URL] {
        switch appType {
        case .sublime, .vscode, .cursor:
            return targetURLs
        case .terminal, .iterm2, .warp:
            return targetURLs.first.map { [getDirectoryURL(for: $0)] } ?? []
        case .codex:
            guard targetURLs.count == 1, let directory = targetURLs.first, directory.isFileURL,
                  (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return []
            }
            // Codex 的新聊天入口通过 path 选择本地项目；不传 prompt，不自动发送任务。
            var components = URLComponents()
            components.scheme = "codex"
            components.host = "new"
            components.queryItems = [
                URLQueryItem(name: "path", value: directory.path),
                URLQueryItem(name: "mode", value: "codex")
            ]
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            return components.url.map { [$0] } ?? []
        case .workbuddy:
            guard targetURLs.count == 1, let directory = targetURLs.first, directory.isFileURL,
                  (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return []
            }
            // WorkBuddy 5.9.2 的文件打开入口只唤起窗口；任务链接才能预选工作目录。
            // 空文本块保留空白输入框，由用户填写并发送任务，不修改权限模式。
            var components = URLComponents()
            components.scheme = "workbuddy"
            components.host = "task"
            components.queryItems = [
                URLQueryItem(name: "action", value: "start"),
                URLQueryItem(name: "cwd", value: directory.path),
                URLQueryItem(name: "promptContentBlocks", value: "[{\"type\":\"text\",\"text\":\"\"}]"),
                URLQueryItem(name: "promptAnimation", value: "none")
            ]
            // Electron 使用 URLSearchParams，字面量 + 必须编码，避免被当成空格。
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            return components.url.map { [$0] } ?? []
        }
    }

    private func getDirectoryURL(for url: URL) -> URL {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
}
