import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    
    fileprivate static var instance: AppDelegate?

    var window: NSWindow!
    private var actionServer: AuthenticatedActionServer?
    private var statusItem: NSStatusItem?
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. 初始化并注册系统自带的右键菜单动作
        registerDefaultActions()
        NSApp.servicesProvider = FinderServicesProvider.shared
        FinderQuickServiceManager.shared.start()
        
        // Disk queues are untrusted. Only authenticated local socket requests reach the dispatcher.
        do {
            actionServer = try AuthenticatedActionServer()
            try actionServer?.start()
        } catch {
            AppLog.error("安全动作服务启动失败: \(error.localizedDescription)", category: .host)
        }

        // 4. 创建 SwiftUI 主设置视图并托管在 NSWindow 中
        let contentView = ContentView()
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.delegate = self // 【关键修复】：指定 Window 代理，使 windowShouldClose 方法能被正确触发
        window.title = "开源右键助手 (RightClickAssistant)"
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.contentView = NSHostingView(rootView: contentView)
        window.orderOut(nil) // 【关键体验优化】：确保主设置窗口初始状态绝对不可见
        
        // 主程序默认保持安静的菜单栏形态；是否展示设置页由启动来源决定。
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        showSettingsWindowIfNeededForLaunch()
        handlePermissionRefreshLaunchIfNeeded()
        
        print("[App] 右键助手宿主程序启动并初始化完成 (安全动作服务就绪)")
        
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        actionServer?.stop()
        FinderQuickServiceManager.shared.stop()
    }
    
    /// 注册默认的一套右键快捷操作
    private func registerDefaultActions() {
        let actions = DefaultActionRegistry.registerAll()
        SharedStorageManager.shared.migrateSettingsIfNeeded(actions: actions)
        ActionConfigCache.shared.preheat()
        print("[App] 已成功注册 \(actions.count) 个核心右键动作")
    }
    
    // MARK: - 系统菜单栏托盘管理
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        // 采用 SF Symbols 原生图标渲染，带 macOS 版本兼容降级。
        // contextualmenu 需要 macOS 14+，旧版本回退到 line.3.horizontal。
        let symbolName: String
        if #available(macOS 14.0, *) {
            symbolName = "contextualmenu"
        } else {
            symbolName = "line.3.horizontal"
        }
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "开源右键助手") {
            image.isTemplate = true // 跟随系统深/浅色菜单栏渲染
            button.image = image
        }
        // 兜底：若 SF Symbol 拉取失败（旧系统、缺资源、降级路径），
        // 让 statusItem 至少有 1 个汉字宽度，避免变成 0 宽不可见。
        if button.image == nil {
            button.title = "右"
        }
        
        let menu = NSMenu(title: "开源右键助手")
        menu.delegate = self
        rebuildStatusMenu(menu)
        statusItem?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let settingsItem = NSMenuItem(title: "打开设置…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "关于右键助手", action: #selector(showAboutDialog), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let silentLaunchItem = NSMenuItem(
            title: "静默启动",
            action: #selector(toggleSilentLaunch(_:)),
            keyEquivalent: ""
        )
        silentLaunchItem.target = self
        silentLaunchItem.state = isSilentLaunchEnabled ? .on : .off
        menu.addItem(silentLaunchItem)

        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(terminateApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private var isSilentLaunchEnabled: Bool {
        SharedStorageManager.shared.getBool(
            forKey: LaunchPresentationPolicy.silentLaunchKey,
            defaultValue: true
        )
    }

    private func showSettingsWindowIfNeededForLaunch() {
        evaluateLaunchPresentation()

        // LSUIElement app 在 didFinishLaunching 时可能还没来得及成为 active/frontmost。
        // 延迟做一次二次判断，避免用户从启动台/Applications 主动打开却看不到窗口。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.evaluateLaunchPresentation()
        }
    }

    private func evaluateLaunchPresentation() {
        guard !window.isVisible else { return }

        let context = LaunchPresentationPolicy.context(
            arguments: CommandLine.arguments,
            appIsActive: NSApp.isActive,
            frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )

        if LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            silentLaunchEnabled: isSilentLaunchEnabled,
            context: context
        ) {
            showSettingsWindow()
        }
    }

    private func handlePermissionRefreshLaunchIfNeeded() {
        guard CommandLine.arguments.contains(LaunchPresentationPolicy.permissionRefreshArgument) else {
            return
        }

        SystemReloader.postConfigChanged()
        SharedHUDManager.show(
            title: "正在刷新 Finder",
            content: "已重新打开右键助手，正在让 Finder 按新权限加载右键菜单",
            isSuccess: true
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let result = SystemReloader.restartFinder()
            DispatchQueue.main.async {
                guard !result.isSuccess else { return }
                SharedHUDManager.show(
                    title: "Finder 重启失败",
                    content: result.errorDescription ?? "请手动重启 Finder 或重新登录后再试",
                    isSuccess: false
                )
            }
        }
    }
    
    @objc private func showSettingsWindow() {
        // 保持在 accessory 模式（无 Dock 图标），仅将窗口前置。
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleSilentLaunch(_ sender: NSMenuItem) {
        let newValue = !isSilentLaunchEnabled
        guard SharedStorageManager.shared.setBool(
            newValue,
            forKey: LaunchPresentationPolicy.silentLaunchKey
        ) else {
            sender.state = isSilentLaunchEnabled ? .on : .off
            SharedHUDManager.show(
                title: "设置保存失败",
                content: "无法写入静默启动设置，请检查共享目录权限后重试。",
                isSuccess: false
            )
            return
        }
        sender.state = newValue ? .on : .off
        SharedHUDManager.show(
            title: newValue ? "静默启动已启用" : "静默启动已关闭",
            content: newValue ? "后台拉起时仅保留菜单栏图标" : "下次启动会直接显示设置窗口",
            iconName: newValue ? "moon.fill" : "macwindow",
            isSuccess: true
        )
    }
    
    @objc private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "关于右键助手"
        
        // 从 Bundle 动态拉取当前最新的全局单源版本号
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        alert.informativeText = """
        开源右键助手 (RightClickAssistant)
        版本: v\(version)
        
        一款免费开源的 macOS 右键菜单增强工具。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        
        alert.window.level = .modalPanel
        alert.window.orderFrontRegardless()
        alert.runModal()
    }
    
    @objc private func terminateApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - NSWindowDelegate (常驻后台静默运行生命周期拦截)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 1. 物理隐藏偏好设置窗口，避免被彻底销毁
        window.orderOut(nil)
        
        // 2. 保持 .accessory 模式，仅隐藏窗口。
        
        SharedStorageManager.shared.writeLog("[App] 偏好设置窗口已被关闭，宿主程序自动降级为 .accessory 常驻后台静默运行中...")
        
        // 3. 返回 false 拦截窗口的实际销毁与主程序自动退出
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }
}

// MARK: - 纯代码 AppKit 生命周期终极托管入口
@main
struct AppMain {
    static func main() {
        print("[AppMain] 纯代码自定义入口启动...")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.instance = delegate
        app.delegate = delegate
        print("[AppMain] 手动绑定 Delegate 成功，即将通过 app.run() 启动事件循环...")
        app.run()
    }
}
