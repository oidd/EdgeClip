# Edge Clip

Edge Clip is a clipboard tool for macOS that keeps recent content close at hand and sends it back where you were working with as little interruption as possible.

Instead of switching away, opening a full clipboard manager, and pasting manually, you can summon a compact panel, choose an item, return to the previous app, and continue typing almost immediately.

## English

### Overview

Edge Clip is designed for people who repeatedly move between text, screenshots, files, and reusable snippets during real work. It focuses on fast recall, low friction, and staying local-first.

The app captures clipboard history, lets you preview or organize it, and helps you paste content back into the previously active app.

### Main Capabilities

- Unified clipboard history for text, images, and files
- Four primary interaction modes:
  - screen-edge summon
  - global hotkey
  - menu bar summon
  - press-and-drag right mouse summon
- Automatic paste-back to the previous app, with graceful fallback when Accessibility permission is unavailable
- Full preview opened with `Space`, including text, images, files, archives, and practical file overviews
- Stack mode for repeated input and continuous paste workflows
- Data processing panel that can split text into stack items by newline, space, comma, period, or custom delimiters
- Favorites system with grouped organization and multi-group references
- Search, filtering, pinning, quick actions, and number-key paste
- Local storage with custom directory migration support

### Four Interaction Modes

Edge Clip currently supports four main ways to open the panel:

1. Summon from the selected screen edge
2. Summon with a global keyboard shortcut
3. Summon from the menu bar item
4. Hold the right mouse button and drag right to open the panel

The right-mouse workflow also supports extra mouse gestures for custom actions such as sending a shortcut or opening another app.

### Preview Experience

Preview is one of the app's core experiences.

- Text supports full preview and selection
- Images support direct full preview
- Files support richer inspection flows instead of just showing a filename
- `Space` opens full preview
- `Esc` closes preview
- Some grouped file flows support left and right navigation

The project has gone through multiple preview iterations and currently keeps full preview as a first-class feature rather than a secondary utility.

### Stack Mode and Data Processing

Stack mode is built for repetitive entry work.

- Collect multiple text items into a stack
- Reorder them by drag and drop
- Consume them in order or reverse order
- Remove single entries without destroying the whole session
- Import text directly from preview into the stack workflow

The data processing panel can turn one piece of text into many stack entries. It supports common separators and custom delimiters, then lets you insert above, insert below, or replace the current stack content.

### Favorites and Favorite Groups

Favorites are not just a star flag.

- Favorite text can be kept for long-term reuse
- Favorites can be organized into groups
- All favorites still exist in a global "all favorites" view
- A single favorite can belong to multiple groups without duplicating content
- Group-specific ordering is supported
- Favorites can be added directly into a target group through context actions

### Paste-Back Behavior

The intended workflow is:

1. You work in any app
2. You summon Edge Clip
3. You choose a history or favorite item
4. Edge Clip writes the item back to the pasteboard
5. Edge Clip restores the previous app
6. If Accessibility permission is available, it sends `Command + V`

If Accessibility permission is not granted, Edge Clip degrades safely:

- it still writes content back to the system pasteboard
- it returns you to the previous app
- you paste manually

### Storage

Edge Clip stores its data locally.

By default, the app uses a unified data root under Application Support. The project also supports moving storage to a custom directory, with migration for:

- `history.json`
- `favorite-snippets.json`
- favorite group data
- asset files

Migration is designed to avoid silent overwrite and roll back on failure.

### Permissions and Privacy

Edge Clip is a local-first utility.

- Clipboard history is stored locally
- Accessibility permission is used for paste automation and advanced interaction features
- Some preview and transfer flows rely on file access mechanisms appropriate for sandboxed macOS apps
- If permission is denied, the app remains usable through reduced behavior instead of becoming unusable

Accessibility permission is especially relevant for:

- automatic paste-back
- right-mouse summon
- extra mouse gestures
- certain stack and preview keyboard bridges

### Current Feature Scope

The current project includes:

- text, image, and file capture
- full preview for text, image, and file content
- stack mode and data processing
- favorite groups
- menu bar integration
- launch at login
- configurable panel behavior and visibility options
- custom storage location migration

### Tech Stack

- Swift 6
- SwiftUI + AppKit
- `NSPasteboard`
- `NSPanel`
- `NSWorkspace`
- `CGEvent`
- `SMAppService`
- XPC helper service for specific supporting tasks

### Project Structure

```text
Edge Clip/
  Core/
  Models/
  Services/
  UI/

Edge Clip Readback Service/
  XPC helper service

Edge Clip.xcodeproj/
  Xcode project
```

### Build From Source

Open in Xcode:

```bash
open "Edge Clip.xcodeproj"
```

Or build from Terminal:

```bash
xcodebuild -project "Edge Clip.xcodeproj" -scheme "Edge Clip" -configuration Debug -derivedDataPath /tmp/EdgeClipDerivedData build
```

---

## 中文

### 项目简介

Edge Clip 是一款面向 macOS 的剪贴板工具，目标是让“刚刚复制过的内容”始终留在手边，并尽可能无打断地回到你原本正在输入的位置。

它不是简单地把系统剪贴板变成一长串历史列表，而是围绕“唤出、定位、预览、组织、回贴”这条真实工作流来设计。

### 主要能力

- 统一管理文本、图片、文件三类剪贴板历史
- 支持四种主要交互方式：
  - 屏幕边缘唤出
  - 全局快捷键唤出
  - 菜单栏唤出
  - 按住鼠标右键向右滑出唤出
- 支持自动回到上一个应用并执行粘贴
- 在没有辅助功能权限时，自动降级为“写回剪贴板并返回应用，由用户手动粘贴”
- 通过 `Space` 打开完整预览，覆盖文本、图片、文件、压缩包等常见场景
- 提供堆栈模式，适合连续录入和反复粘贴
- 提供数据处理面板，可按换行、空格、逗号、句号或自定义分隔符拆分文本并导入堆栈
- 提供收藏能力，并支持收藏分组与多分组归类
- 支持搜索、筛选、数字键快速粘贴、置顶与多种快捷操作
- 支持本地数据根目录迁移

### 四种交互方式

当前稳定支持的四种主唤出方式为：

1. 从选定屏幕边缘唤出
2. 使用全局快捷键唤出
3. 从菜单栏状态项唤出
4. 按住鼠标右键向右滑出唤出

其中右键滑出这条链路还支持附加鼠标手势，可用于触发自定义快捷键或打开其它应用。

### 预览能力

预览是 Edge Clip 的核心体验之一。

- 文本支持完整预览与文本选择
- 图片支持直接完整预览
- 文件支持更丰富的内容查看，而不仅仅是显示文件名
- `Space` 打开完整预览
- `Esc` 关闭完整预览
- 某些成组文件场景支持左右切换

项目已经围绕完整预览做过多轮收口，现在完整预览已经是产品主链路的一部分，而不是附属功能。

### 堆栈与数据处理

堆栈模式适合高频录入、连续粘贴和需要顺序消费文本的工作流。

- 把多条文本收集到同一个堆栈中
- 通过拖拽调整顺序
- 支持顺序消费和倒序消费
- 可单条删除，不必清空整个会话
- 可从文本预览直接导入堆栈流程

数据处理面板可以把一段文本拆成多条堆栈项，支持常见分隔符和自定义分隔符，并可选择插入上方、插入下方或替换当前堆栈内容。

### 收藏与收藏分组

收藏不仅是一个简单的“星标”。

- 收藏文本可作为长期复用内容保留
- 收藏支持分组管理
- 所有收藏始终保留在“全部收藏”视图中
- 同一条收藏可同时属于多个分组，而不会复制内容
- 支持分组内独立排序
- 支持通过右键等上下文动作直接“收藏并加入分组”

### 自动回贴行为

设计目标流程如下：

1. 你在任意应用中工作
2. 唤出 Edge Clip
3. 选择一条历史记录或收藏内容
4. Edge Clip 将内容写回系统剪贴板
5. Edge Clip 恢复上一个应用到前台
6. 若已授予辅助功能权限，则自动发送 `Command + V`

若未授予辅助功能权限，Edge Clip 会安全降级：

- 仍然把内容写回系统剪贴板
- 仍然返回上一个应用
- 但由你自己手动粘贴

### 数据存储

Edge Clip 采用本地存储。

默认情况下，应用会在 `Application Support` 下维护统一数据根目录。同时项目也已经支持把数据迁移到自定义目录，并覆盖以下内容：

- `history.json`
- `favorite-snippets.json`
- 收藏分组数据
- 资源文件目录

迁移流程包含冲突检查与失败回滚，不会静默覆盖已有数据。

### 权限与隐私

Edge Clip 是一款本地优先工具。

- 剪贴板历史保存在本地
- 辅助功能权限主要用于自动粘贴和增强交互能力
- 某些预览与文件转交链路会使用适合沙盒 macOS 应用的文件访问机制
- 即使没有授权，应用也会以降级方式继续可用，而不是直接失效

辅助功能权限目前主要关联到：

- 自动粘贴
- 右键滑出
- 附加鼠标手势
- 某些堆栈和预览相关快捷键桥接

### 当前功能范围

当前项目已经包含：

- 文本、图片、文件采集
- 文本、图片、文件完整预览
- 堆栈模式与数据处理面板
- 收藏分组
- 菜单栏集成
- 开机自启动
- 剪贴面板行为与可见性配置
- 自定义数据目录迁移

### 技术栈

- Swift 6
- SwiftUI + AppKit
- `NSPasteboard`
- `NSPanel`
- `NSWorkspace`
- `CGEvent`
- `SMAppService`
- 用于部分辅助能力的 XPC 服务

### 项目结构

```text
Edge Clip/
  Core/
  Models/
  Services/
  UI/

Edge Clip Readback Service/
  XPC 辅助服务

Edge Clip.xcodeproj/
  Xcode 工程
```

### 从源码运行

使用 Xcode 打开：

```bash
open "Edge Clip.xcodeproj"
```

或通过命令行构建：

```bash
xcodebuild -project "Edge Clip.xcodeproj" -scheme "Edge Clip" -configuration Debug -derivedDataPath /tmp/EdgeClipDerivedData build
```
