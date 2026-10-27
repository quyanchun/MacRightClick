import Foundation
import AppKit
import Darwin

/// 新建文件类型枚举
public enum SupportedFileType: String, CaseIterable, Codable, Identifiable {
    case txt = "txt"
    case pages = "pages"
    case key = "key"
    case numbers = "numbers"
    case md = "md"
    case json = "json"
    case csv = "csv"
    case html = "html"
    case docx = "docx"
    case xlsx = "xlsx"
    case pptx = "pptx"
    case pdf = "pdf"
    
    public var id: String { self.rawValue }
    
    public var extensionName: String {
        return self.rawValue
    }
    
    public var displayName: String {
        switch self {
        case .txt: return "文本文件 (.txt)"
        case .pages: return "Pages 文稿 (.pages)"
        case .key: return "Keynote 演示文稿 (.key)"
        case .numbers: return "Numbers 表格 (.numbers)"
        case .md: return "Markdown 文档 (.md)"
        case .json: return "JSON 配置文件 (.json)"
        case .csv: return "CSV 表格 (.csv)"
        case .html: return "HTML 网页 (.html)"
        case .docx: return "Word 文档 (.docx)"
        case .xlsx: return "Excel 表格 (.xlsx)"
        case .pptx: return "PPT 演示文稿 (.pptx)"
        case .pdf: return "PDF 电子书 (.pdf)"
        }
    }
    
    /// 获取每种类型的空白默认字节，确保 Office 等软件能够正常打开而非提示损坏
    public func contents(templateDirectory: URL? = nil) throws -> Data {
        switch self {
        // Office 三件套需要完整的最小骨架（[Content_Types].xml + _rels + 主体 part），
        // 否则 Word/Excel/PowerPoint/Pages 双击会提示「文件已损坏」。
        // 实际骨架以二进制方式打包到 .app/Contents/Resources/Templates/blank.<ext>，运行时读取。
        case .docx, .xlsx, .pptx, .pages, .key, .numbers:
            let url = templateDirectory?.appendingPathComponent("blank.\(rawValue)")
                ?? Bundle.main.url(forResource: "blank", withExtension: rawValue, subdirectory: "Templates")
            guard let url else { throw CocoaError(.fileReadNoSuchFile) }
            let data = try Data(contentsOf: url)
            guard data.count > 100, data.starts(with: [0x50, 0x4b]) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return data
        case .html:
            return """
            <!doctype html>
            <html lang="zh-CN">
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>未命名</title>
            </head>
            <body>
            </body>
            </html>
            """.data(using: .utf8) ?? Data()
        case .pdf:
            var pdf = "%PDF-1.4\n"
            let objects = [
                "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
                "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
                "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>\nendobj\n",
                "4 0 obj\n<< /Length 0 >>\nstream\nendstream\nendobj\n"
            ]
            var offsets: [Int] = []
            for object in objects {
                offsets.append(pdf.utf8.count)
                pdf += object
            }
            let xrefOffset = pdf.utf8.count
            pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
            for offset in offsets {
                pdf += String(format: "%010d 00000 n \n", offset)
            }
            pdf += """
            trailer
            << /Size \(objects.count + 1) /Root 1 0 R >>
            startxref
            \(xrefOffset)
            %%EOF
            """
            return pdf.data(using: .ascii) ?? Data()
        default:
            return Data() // 文本类、JSON 等可直接生成 0 字节文件
        }
    }
}

/// 新建文件动作实现类
public final class NewFileAction: MenuAction {
    public let actionId: String
    public let localizedTitle: String
    public let iconName: String?
    public let category: ActionCategory = .newFile
    
    public let fileType: SupportedFileType
    private let customTemplateURL: URL?

    public var tier: ActionTier {
        switch fileType {
        case .txt, .md, .pdf, .pages, .key, .numbers, .docx, .xlsx, .pptx:
            return .essential
        case .json, .csv, .html:
            return .professional
        }
    }

    public var isEnabledByDefault: Bool {
        return tier == .essential
    }
    
    public init(fileType: SupportedFileType, customTemplateURL: URL? = nil) {
        self.fileType = fileType
        self.customTemplateURL = customTemplateURL
        self.actionId = "guyue.action.newfile.\(fileType.rawValue)"
        self.localizedTitle = "新建 \(fileType.displayName)"
        
        switch fileType {
        case .txt: self.iconName = "doc.text"
        case .pages: self.iconName = "doc.richtext"
        case .key: self.iconName = "play.rectangle"
        case .numbers: self.iconName = "tablecells.fill"
        case .md: self.iconName = "doc.text.fill"
        case .json: self.iconName = "curlybraces"
        case .csv: self.iconName = "tablecells"
        case .html: self.iconName = "globe"
        case .docx: self.iconName = "doc.richtext"
        case .xlsx: self.iconName = "tablecells.fill"
        case .pptx: self.iconName = "play.rectangle"
        case .pdf: self.iconName = "doc.fill"
        }
    }
    
    /// Publish with exclusive rename so concurrent creates and dangling links cannot be overwritten.
    public func createFile(in directory: URL, templateDirectory: URL? = nil) throws -> URL {
        let data: Data
        if let customTemplateURL {
            data = try Data(contentsOf: customTemplateURL)
        } else {
            data = try fileType.contents(templateDirectory: templateDirectory)
        }
        let stagingDirectory = directory.appendingPathComponent(".rightclick-new-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }
        let staged = stagingDirectory.appendingPathComponent("document")
        try data.write(to: staged)
        var counter = 0
        while true {
            let name = counter == 0 ? "未命名" : "未命名 \(counter)"
            let destination = directory.appendingPathComponent("\(name).\(fileType.extensionName)")
            do {
                try FilePublication.publish(staged, to: destination)
                return destination
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST) {
                counter += 1
            }
        }
    }

    public func execute(targetURLs: [URL]) -> Bool {
        guard let targetURL = targetURLs.first else {
            print("[NewFileAction] 错误: 没有选中目标目录或路径")
            return false
        }
        
        // 1. 确定要在哪一个文件夹中创建新文件
        let destinationDir: URL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) && isDir.boolValue {
            destinationDir = targetURL
        } else {
            destinationDir = targetURL.deletingLastPathComponent()
        }
        
        do {
            let finalURL = try createFile(in: destinationDir)
            print("[NewFileAction] 文件创建成功: \(finalURL.path)")
            
            SharedHUDManager.show(
                title: "新建成功",
                content: "已生成并高亮: \(finalURL.lastPathComponent)",
                isSuccess: true
            )
            
            // 可选：在 Finder 中高亮显示或者直接打开该文件
            DispatchQueue.main.async {
                NSWorkspace.shared.selectFile(finalURL.path, inFileViewerRootedAtPath: destinationDir.path)
            }
            return true
        } catch {
            print("[NewFileAction] 创建文件失败: \(error.localizedDescription)")
            SharedHUDManager.show(
                title: "新建失败",
                content: error.localizedDescription,
                isSuccess: false
            )
            return false
        }
    }
}
