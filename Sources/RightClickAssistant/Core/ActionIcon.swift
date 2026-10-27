import AppKit
import UniformTypeIdentifiers

/// Shared by settings and Finder. Native document/application icons retain their familiar identity.
public enum ActionIcon {
    // NSCache synchronizes access; images are immutable after insertion.
    private nonisolated(unsafe) static let images = NSCache<NSString, NSImage>()

    public static func image(for action: MenuAction) -> NSImage {
        if let file = action as? NewFileAction {
            // Browser PDF associations should not make this action look like “new webpage”.
            if file.fileType == .pdf { return asset("pdf", fallback: "doc.richtext") }
            return cached("file.\(file.fileType.rawValue)") {
                NSWorkspace.shared.icon(for: UTType(filenameExtension: file.fileType.rawValue) ?? .data)
            }
        }
        if let bundleID = action.associatedBundleIdentifier,
           let app = InstalledAppRegistry.shared.url(for: bundleID) {
            return cached("app.\(app.path)") { NSWorkspace.shared.icon(forFile: app.path) }
        }
        let name: String
        switch action.iconName {
        case "scissors": name = "cut"
        case "doc.on.clipboard": name = "paste"
        case "pencil.and.outline": name = "name"
        case "trash.slash": name = "trash"
        case "arrow.right.doc.on.clipboard": name = "move"
        case "doc.on.doc": name = "copy"
        case "qrcode": name = "qr"
        case "number.square", "number.square.fill": name = "hash"
        case "photo", "photo.fill": name = "image"
        case "eye", "eye.slash": name = "eye"
        default: name = action.category == .utility ? "tools" : "path"
        }
        return asset(name, fallback: action.iconName ?? "gearshape")
    }

    public static func groupImage(title: String) -> NSImage {
        switch title {
        case "新建文件": return asset("new-file", fallback: "doc.badge.plus")
        case "实用工具": return asset("tools", fallback: "wrench.and.screwdriver")
        case "终端/编辑器": return asset("terminal", fallback: "terminal")
        default: return asset("folder", fallback: "folder")
        }
    }

    private static func asset(_ name: String, fallback: String) -> NSImage {
        cached("asset.\(name)") {
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "ActionIcons"),
               let image = NSImage(contentsOf: url) { return image }
            let symbol = NSImage(systemSymbolName: fallback, accessibilityDescription: nil)
            return symbol?.withSymbolConfiguration(.init(paletteColors: [.systemBlue, .systemTeal])) ?? NSImage(size: NSSize(width: 20, height: 20))
        }
    }

    private static func cached(_ key: String, make: () -> NSImage) -> NSImage {
        if let image = images.object(forKey: key as NSString) { return image }
        let image = (make().copy() as? NSImage) ?? make()
        image.size = NSSize(width: 20, height: 20)
        image.isTemplate = false
        images.setObject(image, forKey: key as NSString)
        return image
    }
}
