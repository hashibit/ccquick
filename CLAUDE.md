# CCQuick — CLAUDE.md

## 项目概述

macOS 菜单栏应用。通过全局快捷键唤出输入窗口，在后台运行 Claude Code 执行任务，结果通过系统通知推送给用户。

## 技术栈

- **语言**：Swift 5.9+
- **UI**：SwiftUI + AppKit（NSStatusItem、NSPanel）
- **并发**：Swift Concurrency（async/await）
- **存储**：文件系统（`~/.ccquick/` + `meta.json`）
- **通知**：UserNotifications framework
- **包管理**：Swift Package Manager

## 目录结构

```
ccquick/
├── CCQuick.xcodeproj/
├── CCQuick/
│   ├── App/
│   │   ├── CCQuickApp.swift        # @main，LSUIElement
│   │   └── AppDelegate.swift
│   ├── MenuBar/
│   │   ├── StatusItemController.swift   # NSStatusItem，badge
│   │   └── MenuBuilder.swift
│   ├── InputWindow/
│   │   ├── InputWindowController.swift  # NSPanel
│   │   └── InputView.swift              # SwiftUI
│   ├── Task/
│   │   ├── TaskManager.swift            # 任务生命周期
│   │   ├── TaskRunner.swift             # Process + Pipe
│   │   ├── TaskStore.swift              # meta.json 读写
│   │   └── Task.swift                   # 数据模型
│   ├── Notifications/
│   │   └── NotificationService.swift
│   └── History/
│       ├── HistoryWindowController.swift
│       └── HistoryView.swift
├── Plans.md
└── idea.md
```

## 核心设计规则

- `LSUIElement = true` — 不显示 Dock 图标
- Claude CLI 调用：`claude --dangerously-skip-permissions -p "<prompt>"` 非交互模式执行
- 工作目录：每次任务创建 `~/.ccquick/YYYYMMDDHHM-slug/`
- Tray badge 通过动态绘制 `NSImage` 实现（macOS 无原生 tray badge API）
- 全局快捷键：`NSEvent.addGlobalMonitorForEvents`（需要辅助功能权限）

## 编码规范

- SwiftUI 与 AppKit 混用时，通过 `NSViewRepresentable` / `NSWindowController` 桥接
- 异步处理使用 `async/await` + `@MainActor`
- 错误通过 `Result<T, Error>` 或 `throws` 传播，禁止 silent fail
- 文件名与组件名一一对应

## 开发命令

```bash
# 构建
xcodebuild -scheme CCQuick -configuration Debug build

# 测试
xcodebuild -scheme CCQuick -configuration Debug test
```
