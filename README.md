# MacRightClick

[English](README_EN.md) · [下载安装包](https://github.com/quyanchun/MacRightClick/releases/latest)

macOS Finder 右键菜单助手。把新建文件、路径复制、终端和常用文件操作放进右键菜单，并按自己的习惯分组、排序和启用。

> 本项目基于 **[guyue55/MacRightClick](https://github.com/guyue55/MacRightClick)** 修改，是独立维护的衍生版本。感谢原作者的开源贡献；原项目版权与 [MIT 许可证](LICENSE) 均予以保留。

## 当前界面

以下截图来自当前版本的实际运行界面，展示配置可自行调整。

| 动作分组与排序 | 高级动作与外部工具 |
| :---: | :---: |
| <img src="docs/screenshots/menu-editor.png" width="560" alt="当前版本的动作编辑器，支持分组、拖动排序和独立开关" /> | <img src="docs/screenshots/tools-current.png" width="560" alt="当前版本的高级动作和外部工具设置" /> |

## 主要功能

- **自定义菜单**：创建与命名分组，拖动排序，将动作移入分组或放在一级菜单。
- **新建文件**：文本、Markdown、JSON、CSV、HTML、PDF、Word、Excel、PowerPoint，以及 Pages、Numbers、Keynote 模板。
- **文件与路径**：剪切粘贴、复制与移动、文件名和路径复制，支持 Shell 安全路径及 Git 相对路径。
- **终端与编辑器**：在已安装的终端、编辑器中打开目标，支持 Codex、WorkBuddy 的目录入口。
- **实用工具**：MD5 / SHA-256、二维码、PNG / JPEG 转换，以及 Finder 作用范围和状态诊断。

高级动作可能删除文件或改变系统状态，执行前会确认。部分菜单项需要对应的第三方应用已安装。

## 下载与使用

要求 **macOS 13 或更新版本**；Universal 2 安装包同时包含 **Apple Silicon（arm64）和 Intel（x86_64）**。

1. 从本仓库的 [Releases](https://github.com/quyanchun/MacRightClick/releases) 下载 DMG 或 ZIP，将 `RightClickAssistant.app` 放入“应用程序”。
2. 打开应用，在“动作”中配置菜单，在“Finder”中检查扩展是否启用。
3. 若 macOS 阻止首次打开，可在确认下载来源后使用 Control 点击“打开”，或到“系统设置 → 隐私与安全性”中手动允许。

当前 `1.2.1` 为 **Ad-hoc 签名、未经 Apple 公证**的社区构建。完全磁盘访问只影响受保护目录中的文件操作，并非显示右键菜单的必要条件。安装包不包含个人设置或动作队列。

## 从源码构建

需要 Swift 6 和 Xcode Command Line Tools：

```sh
git clone https://github.com/quyanchun/MacRightClick.git
cd MacRightClick
SKIP_DMG_LAYOUT=1 bash Scripts/build.sh
```

输出：`build/RightClickAssistant.app`、`build/RightClickAssistant.dmg` 和 `build/RightClickAssistant.zip`。`SKIP_DMG_LAYOUT=1` 跳过 Finder 窗口的自动排版，不影响安装包内容。针对当前定制功能的回归检查：`bash Scripts/test_regressions.sh`。

## 来源与许可

- 原项目：[guyue55/MacRightClick](https://github.com/guyue55/MacRightClick)
- 当前维护仓库：[quyanchun/MacRightClick](https://github.com/quyanchun/MacRightClick)
- 许可证：[MIT](LICENSE)
