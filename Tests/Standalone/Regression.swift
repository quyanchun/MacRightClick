import Foundation
import AppKit
import PDFKit
import Darwin

private final class Results: @unchecked Sendable {
    let lock = NSLock()
    var values: [Bool] = []
    func append(_ value: Bool) { lock.lock(); values.append(value); lock.unlock() }
}

@main
struct Regression {
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "Regression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS: \(message)")
    }
    static func rejected(_ block: () throws -> Void) -> Bool {
        do { try block(); return false } catch { return true }
    }
    static func main() throws {
        setbuf(stdout, nil)
        let args = CommandLine.arguments
        if args.count > 1 && args[1] == "--client" {
            try runClient(endpointURL: URL(fileURLWithPath: args[2]), expected: args[3] == "true")
            return
        }
        let root = URL(fileURLWithPath: args[1], isDirectory: true)
        let templates = URL(fileURLWithPath: args[2], isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let moves = root.appendingPathComponent("moves")
        try manager.createDirectory(at: moves, withIntermediateDirectories: true)
        let src = moves.appendingPathComponent("source")
        let dest = moves.appendingPathComponent("destination")
        try Data("source".utf8).write(to: src)
        try Data("original".utf8).write(to: dest)
        try require(!FileManageAction.crossVolumeMove(from: src, to: dest), "existing target rejects move")
        try require(Data(contentsOf: dest) == Data("original".utf8), "existing destination preserved")
        try require(Data(contentsOf: src) == Data("source".utf8), "source preserved on collision")
        try manager.removeItem(at: dest)
        let failedCopy = FileManageAction.crossVolumeMove(from: src, to: dest, copy: { _, staged in
            try Data("partial".utf8).write(to: staged)
            throw CocoaError(.fileWriteOutOfSpace)
        }, sanityCheck: { _ in })
        try require(!failedCopy && !manager.fileExists(atPath: dest.path) && manager.fileExists(atPath: src.path), "partial copy failure leaves source and cleans staging")
        let failedCheck = FileManageAction.crossVolumeMove(from: src, to: dest, copy: { try manager.copyItem(at: $0, to: $1) }, sanityCheck: { _ in throw CocoaError(.fileReadCorruptFile) })
        try require(!failedCheck && !manager.fileExists(atPath: dest.path), "validation failure never publishes")
        let raced = FileManageAction.crossVolumeMove(from: src, to: dest, copy: { from, staged in
            try manager.copyItem(at: from, to: staged)
            try Data("racing writer".utf8).write(to: dest)
        }, sanityCheck: { _ in })
        try require(!raced && Data(contentsOf: dest) == Data("racing writer".utf8), "racing destination preserved")
        try manager.removeItem(at: dest)
        try manager.createSymbolicLink(at: dest, withDestinationURL: moves.appendingPathComponent("missing"))
        try require(!FileManageAction.crossVolumeMove(from: src, to: dest), "dangling symlink is not overwritten")
        try require(manager.destinationOfSymbolicLink(atPath: dest.path).hasSuffix("missing"), "dangling symlink preserved")
        try manager.removeItem(at: dest)
        try require(FileManageAction.crossVolumeMove(from: src, to: dest), "ordinary staged move succeeds")
        try require(!manager.fileExists(atPath: src.path) && Data(contentsOf: dest) == Data("source".utf8), "successful move preserves bytes")
        try manager.removeItem(at: dest)
        try Data().write(to: src)
        try require(FileManageAction.crossVolumeMove(from: src, to: dest), "empty file moves successfully")
        try manager.removeItem(at: dest)
        try manager.createDirectory(at: src, withIntermediateDirectories: false)
        try Data("nested".utf8).write(to: src.appendingPathComponent("child"))
        try require(FileManageAction.crossVolumeMove(from: src, to: dest), "directory moves successfully")
        try require(Data(contentsOf: dest.appendingPathComponent("child")) == Data("nested".utf8), "directory contents preserved")
        try require(manager.contentsOfDirectory(atPath: moves.path).allSatisfy { !$0.hasPrefix(".rightclick-") }, "move staging cleaned")

        let locked = root.appendingPathComponent("locked-source-parent")
        try manager.createDirectory(at: locked, withIntermediateDirectories: false)
        let lockedSource = locked.appendingPathComponent("source")
        let retained = moves.appendingPathComponent("retained-copy")
        try Data("complete copy".utf8).write(to: lockedSource)
        chmod(locked.path, 0o555)
        let removalFailed = !FileManageAction.crossVolumeMove(from: lockedSource, to: retained)
        chmod(locked.path, 0o755)
        try require(removalFailed && Data(contentsOf: retained) == Data("complete copy".utf8), "source deletion failure retains complete destination")

        let docs = root.appendingPathComponent("documents")
        try manager.createDirectory(at: docs, withIntermediateDirectories: true)
        for type in SupportedFileType.allCases {
            let action = NewFileAction(fileType: type)
            let first = try action.createFile(in: docs, templateDirectory: templates)
            let second = try action.createFile(in: docs, templateDirectory: templates)
            try require(first != second && Data(contentsOf: first) == type.contents(templateDirectory: templates), "\(type.rawValue) valid template bytes and unique name")
        }
        try require(PDFDocument(url: docs.appendingPathComponent("未命名.pdf"))?.pageCount == 1, "PDF parses as one page")
        let missing = root.appendingPathComponent("no-templates")
        for type in [SupportedFileType.pages, .key, .numbers, .docx, .xlsx, .pptx] {
            try require(rejected { _ = try NewFileAction(fileType: type).createFile(in: docs, templateDirectory: missing) }, "missing \(type.rawValue) template fails instead of creating corrupt file")
        }
        let link = docs.appendingPathComponent("未命名 2.txt")
        try manager.createSymbolicLink(at: link, withDestinationURL: docs.appendingPathComponent("missing"))
        let third = try NewFileAction(fileType: .txt).createFile(in: docs, templateDirectory: templates)
        try require(third.lastPathComponent == "未命名 3.txt", "new-file skips dangling symlink")
        let results = Results()
        DispatchQueue.concurrentPerform(iterations: 24) { _ in
            do { _ = try NewFileAction(fileType: .txt).createFile(in: docs, templateDirectory: templates); results.append(true) }
            catch { results.append(false) }
        }
        try require(results.values.count == 24 && results.values.allSatisfy { $0 }, "24 concurrent creates all succeed")
        try require(manager.contentsOfDirectory(atPath: docs.path).filter { $0.hasSuffix(".txt") }.count == 28, "concurrent creates never overwrite")
        try require(manager.contentsOfDirectory(atPath: docs.path).allSatisfy { !$0.hasPrefix(".rightclick-") }, "new-file staging cleaned")
        let actions = DefaultActionRegistry.makeActions()
        try require(!actions.contains { $0.actionId == "guyue.action.terminal.cursor" }, "Cursor entry removed from registry")
        let pathAction = FileManageAction(type: .copyPath)
        try require(pathAction.isAvailable(for: [docs], isContainer: true), "blank-area copy path available")
        try require(!pathAction.isAvailable(for: [], isContainer: true), "copy path needs a target directory")
        for type in [FileManageType.cut, .permanentDelete, .moveTo, .copyTo] {
            try require(!FileManageAction(type: type).isAvailable(for: [docs], isContainer: true), "destructive/item action remains hidden on background: \(type)")
        }
        let editorFile = docs.appendingPathComponent("中文 空格 ' $ 文件.md")
        let secondEditorFile = docs.appendingPathComponent("--second.txt")
        try Data("selected file contents".utf8).write(to: editorFile)
        try Data("second file contents".utf8).write(to: secondEditorFile)
        for type in [TerminalEditorType.sublime, .vscode, .cursor] {
            let action = TerminalOpenAction(type: type)
            try require(action.urlsToOpen(for: [editorFile]) == [editorFile], "\(type) opens the selected file, not its parent")
            try require(action.urlsToOpen(for: [editorFile, secondEditorFile]) == [editorFile, secondEditorFile], "\(type) preserves multiple files and special characters")
            try require(action.urlsToOpen(for: [docs]) == [docs], "\(type) still opens a selected folder")
            try require(action.urlsToOpen(for: []).isEmpty, "\(type) rejects empty selection")
        }
        for type in [TerminalEditorType.terminal, .iterm2, .warp] {
            let action = TerminalOpenAction(type: type)
            try require(action.urlsToOpen(for: [editorFile]).map(\.path) == [docs.path], "\(type) enters the selected file's parent directory")
            try require(action.urlsToOpen(for: [docs]) == [docs], "\(type) preserves a selected directory")
        }
        let registry = InstalledAppRegistry.shared
        let codex = TerminalOpenAction(type: .codex)
        let codexDirectory = docs.appendingPathComponent("Codex 中文 + & # ? % ' 文件夹")
        try manager.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        let codexURL = codex.urlsToOpen(for: [codexDirectory]).first!
        let codexComponents = URLComponents(url: codexURL, resolvingAgainstBaseURL: false)!
        let codexQuery = Dictionary(uniqueKeysWithValues: codexComponents.queryItems!.map { ($0.name, $0.value!) })
        try require(codexURL.scheme == "codex" && codexURL.host == "new", "Codex uses the new-chat project entry")
        try require(codexQuery == ["path": codexDirectory.path, "mode": "codex"] && codexComponents.fragment == nil, "Codex selects exact directory without prompt or permission changes")
        try require(codexComponents.percentEncodedQuery?.contains("+") == false && codexComponents.percentEncodedQuery?.contains("%2B") == true, "Codex encodes literal plus for URLSearchParams")
        try require(codex.urlsToOpen(for: []).isEmpty && codex.urlsToOpen(for: [editorFile]).isEmpty, "Codex rejects empty selection and files")
        try require(codex.urlsToOpen(for: [docs, codexDirectory]).isEmpty && codex.urlsToOpen(for: [missing]).isEmpty, "Codex rejects multiple or missing directories")
        registry.overrideResolverForTesting = { $0 == "com.openai.codex" ? URL(fileURLWithPath: "/Applications/ChatGPT.app") : nil }
        try require(codex.isAvailable(for: [codexDirectory]) && codex.isAvailable(for: [docs], isContainer: true), "Codex detected by bundle ID including ChatGPT app name")
        registry.overrideResolverForTesting = { _ in nil }
        try require(!codex.isAvailable(for: [codexDirectory]), "missing Codex stays unavailable")
        try require(actions.contains { $0.actionId == codex.actionId } && codex.isEnabledByDefault, "Codex registered and enabled by default")
        let buddy = TerminalOpenAction(type: .workbuddy)
        let buddyDirectory = docs.appendingPathComponent("WorkBuddy 中文 & # + ? % ' 文件夹")
        try manager.createDirectory(at: buddyDirectory, withIntermediateDirectories: true)
        let buddyURL = buddy.urlsToOpen(for: [buddyDirectory]).first!
        let buddyComponents = URLComponents(url: buddyURL, resolvingAgainstBaseURL: false)!
        let buddyQuery = Dictionary(uniqueKeysWithValues: buddyComponents.queryItems!.map { ($0.name, $0.value!) })
        try require(buddyURL.scheme == "workbuddy" && buddyURL.host == "task", "WorkBuddy uses task deep link instead of file-open")
        try require(buddyQuery["cwd"] == buddyDirectory.path && buddyComponents.fragment == nil, "WorkBuddy special-character directory round trips without query injection")
        try require(buddyComponents.percentEncodedQuery?.contains("+") == false && buddyComponents.percentEncodedQuery?.contains("%2B") == true, "WorkBuddy encodes literal plus for Electron URLSearchParams")
        try require(buddyQuery["promptContentBlocks"] == "[{\"type\":\"text\",\"text\":\"\"}]" && buddyQuery["prompt"] == nil && buddyQuery["permissionMode"] == nil, "WorkBuddy opens blank composer without changing permissions")
        try require(buddy.urlsToOpen(for: []).isEmpty && buddy.urlsToOpen(for: [editorFile]).isEmpty, "WorkBuddy rejects empty selection and files")
        try require(buddy.urlsToOpen(for: [docs, buddyDirectory]).isEmpty && buddy.urlsToOpen(for: [missing]).isEmpty, "WorkBuddy rejects multiple or missing folders")
        registry.overrideResolverForTesting = { $0 == "com.tencent.workbuddy.mac" ? URL(fileURLWithPath: "/Applications/WorkBuddy.app") : nil }
        try require(buddy.isAvailable(for: [buddyDirectory]) && buddy.isAvailable(for: [docs], isContainer: true), "WorkBuddy available for selected folder and folder background")
        registry.overrideResolverForTesting = { _ in nil }
        try require(!buddy.isAvailable(for: [buddyDirectory]), "missing WorkBuddy stays unavailable")
        registry.overrideResolverForTesting = { $0 == "com.sublimetext.4" ? URL(fileURLWithPath: "/Applications/Sublime Text.app") : nil }
        try require(TerminalOpenAction(type: .sublime).isAvailable(for: [docs]), "Sublime Text 4 detected")
        registry.overrideResolverForTesting = { $0 == "com.sublimetext.3" ? URL(fileURLWithPath: "/Applications/Sublime Text 3.app") : nil }
        try require(TerminalOpenAction(type: .sublime).isAvailable(for: [docs]), "Sublime Text 3 fallback detected")
        registry.overrideResolverForTesting = { _ in nil }
        try require(!TerminalOpenAction(type: .sublime).isAvailable(for: [docs]), "missing Sublime stays unavailable")
        registry.overrideResolverForTesting = nil
        for mode in MenuLayoutMode.allCases {
            let layout = FinderMenuLayoutBuilder.build(actions: actions, mode: mode, isEnabled: { _ in true }, isFavorite: { _ in true }, isAvailable: { _ in true })
            guard case let .submenu(title, ids) = layout.first else { fatalError("No submenu") }
            try require(title == "新建文件" && ids.count == 12, "\(mode) groups all formats into one submenu")
            let expected = ["txt", "pages", "key", "numbers", "docx", "xlsx", "pptx"].map { "guyue.action.newfile.\($0)" }
            try require(Array(ids.prefix(7)) == expected, "\(mode) matches screenshot format order")
            let utilitySections = layout.filter { if case .submenu(title: "实用工具", actionIds: _) = $0 { return true }; return false }
            try require(utilitySections.count == 1, "\(mode) has exactly one utility submenu, including favorites")
            if case let .submenu(_, utilityIDs) = utilitySections.first {
                try require(Set(utilityIDs) == Set(actions.filter { $0.category == .utility }.map(\.actionId)), "\(mode) utility submenu contains every utility")
            }
            let all = layout.flatMap { section -> [String] in
                switch section { case let .directItems(ids), let .submenu(_, ids): return ids; case .separator: return [] }
            }
            try require(all.count == Set(all).count && all.count == actions.count, "\(mode) favorites have no duplicates or missing actions")
        }
        let hidden = FinderMenuLayoutBuilder.build(actions: actions, mode: .flat, isEnabled: { $0.category != .newFile }, isFavorite: { _ in false }, isAvailable: { _ in true })
        try require(!hidden.contains { if case .submenu(title: "新建文件", actionIds: _) = $0 { return true }; return false }, "empty new-file submenu hidden")
        let noUtilities = FinderMenuLayoutBuilder.build(actions: actions, mode: .flat, isEnabled: { $0.category != .utility }, isFavorite: { _ in false }, isAvailable: { _ in true })
        try require(!noUtilities.contains { if case .submenu(title: "实用工具", actionIds: _) = $0 { return true }; return false }, "empty utility submenu hidden")
        let wordID = "guyue.action.newfile.docx"
        let txtID = "guyue.action.newfile.txt"
        var custom = MenuConfiguration.initial(actions: actions, mode: .flat, favorites: [])
        let fileGroup = custom.entries.first { $0.title == "新建文件" }!.id
        try require(custom.move(wordID, before: custom.entries.first!.id), "Word can be dragged from submenu to first level")
        try require(custom.entries.first?.id == wordID, "promoted Word is first at root")
        let customSections = FinderMenuLayoutBuilder.build(actions: actions, mode: .grouped, configuration: custom,
            isEnabled: { _ in true }, isFavorite: { _ in true }, isAvailable: { _ in true })
        try require(customSections.first == .directItems(actionIds: [wordID]), "custom placement overrides legacy grouping and favorites")
        try require(!custom.entries.first(where: { $0.id == fileGroup })!.actionIDs.contains(wordID), "promoted action removed from old submenu")
        let saved = custom
        try require(!custom.move(fileGroup, toGroup: fileGroup) && custom == saved, "nested groups rejected without changing layout")
        try require(!custom.move(wordID, toGroup: "missing") && custom == saved, "invalid drop target cannot lose action")
        try require(custom.move(wordID, toGroup: fileGroup, before: txtID), "Word can move back into submenu before TXT")
        try require(custom.entries.first(where: { $0.id == fileGroup })?.actionIDs.first == wordID, "within-group order preserved")
        custom.nudge(wordID, by: 1)
        try require(custom.entries.first(where: { $0.id == fileGroup })?.actionIDs.first == txtID, "arrow reorder works inside group")
        let newGroup = MenuEntry.group("办公")
        custom.entries.append(newGroup)
        try require(custom.move(wordID, toGroup: newGroup.id), "action can move into a newly created group")
        let customStorage = SharedStorageManager(sharedContainerURLOverride: root.appendingPathComponent("settings"))
        try require(customStorage.setMenuConfiguration(custom), "custom layout saved atomically")
        try require(customStorage.menuConfiguration == custom, "custom layout persisted and reloaded")
        let disabledLayout = FinderMenuLayoutBuilder.build(actions: actions, mode: .flat, configuration: custom,
            isEnabled: { $0.actionId != wordID }, isFavorite: { _ in false }, isAvailable: { _ in true })
        try require(!disabledLayout.contains { if case .submenu(title: "办公", actionIds: _) = $0 { return true }; return false }, "group with only disabled actions stays hidden")
        try require(customStorage.menuConfiguration?.entries.last?.actionIDs == [wordID], "disabled action retains saved position")
        custom.removeGroup(newGroup.id)
        try require(custom.entries.last?.id == wordID, "removing a group promotes children rather than deleting actions")
        let corrupt = MenuConfiguration(entries: [.action(wordID), .group("重复", actions: [wordID, txtID, "unknown"]), .action("unknown")]).normalized(actions: actions)
        let allCustomIDs = corrupt.entries.flatMap { $0.isGroup ? $0.actionIDs : [$0.id] }
        try require(allCustomIDs.count == Set(allCustomIDs).count && Set(allCustomIDs) == Set(actions.map(\.actionId)), "normalization removes duplicates/unknown IDs and preserves new actions")
        try require(customStorage.applyActionProfile(.essential, actions: actions) && customStorage.menuConfiguration?.entries.last?.id == newGroup.id, "action profile can be applied independently")
        let valid = SharedActionEvent(id: UUID().uuidString, createdAt: Date().timeIntervalSince1970, actionId: "test", paths: [docs.path])
        try require(AuthenticatedActionValidation.decode(JSONEncoder().encode(valid)) == valid, "valid authenticated payload accepted")
        for event in [
            SharedActionEvent(id: "bad", createdAt: valid.createdAt, actionId: "test", paths: [docs.path]),
            SharedActionEvent(id: valid.id, createdAt: 1, actionId: "test", paths: [docs.path]),
            SharedActionEvent(id: valid.id, createdAt: valid.createdAt, actionId: "test", paths: ["relative"]),
            SharedActionEvent(id: valid.id, createdAt: valid.createdAt, actionId: "test", paths: ["/tmp/\0bad"]),
            SharedActionEvent(id: valid.id, createdAt: valid.createdAt, actionId: "test", paths: []),
            SharedActionEvent(id: valid.id, createdAt: valid.createdAt, actionId: "test", paths: [docs.path], schemaVersion: 1)
        ] {
            try require(rejected { _ = try AuthenticatedActionValidation.decode(JSONEncoder().encode(event)) }, "malformed/stale payload rejected")
        }
        try require(rejected { _ = try AuthenticatedActionValidation.decode(Data(repeating: 0, count: 262_145)) }, "oversized payload rejected")
        let endpoint = root.appendingPathComponent("test.endpoint")
        let received = Results()
        let executable = URL(fileURLWithPath: args[0])
        let server = try AuthenticatedActionServer(trustedClientBundle: executable) { _ in received.append(true); return true }
        try server.start(endpointURL: endpoint)
        defer { server.stop() }
        for (binary, expected) in [(executable, true), (executable.deletingLastPathComponent().appendingPathComponent("untrusted-client"), false)] {
            let child = Process()
            child.executableURL = binary
            child.arguments = ["--client", endpoint.path, String(expected)]
            try child.run()
            let deadline = Date().addingTimeInterval(20)
            while child.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            if child.isRunning { child.terminate(); throw CocoaError(.executableRuntimeMismatch) }
            try require(child.terminationStatus == 0, expected ? "signed client request and replay checks pass" : "differently signed client rejected by peer signature")
        }
        try require(received.values.count == 1, "only one authorized action executed, replay and impostor did not execute")
        print("ALL REGRESSIONS PASSED; test documents: \(docs.path)")
    }

    static func runClient(endpointURL: URL, expected: Bool) throws {
        let host = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("regression")
        let event = SharedActionEvent(id: UUID().uuidString, createdAt: Date().timeIntervalSince1970, actionId: "test", paths: ["/tmp/test"])
        for wanted in expected ? [true, false] : [false] {
            let accepted = try AuthenticatedActionClient.send(event: event, hostBundle: host, endpointURL: endpointURL)
            try require(accepted == wanted, "authenticated socket reply = \(wanted)")
        }
    }
}
