# CCQuick — 设计文档

## 产品定位

macOS 菜单栏工具，通过全局快捷键唤出输入框，后台运行 Claude Code 执行任务，结果通过系统通知推送。快速发起、后台执行、随时查看。

---

## 核心交互流程

```
全局快捷键
    ↓
弹出输入框（类 Alfred 风格）
    ↓
用户输入指令 → 回车
    ↓
创建工作目录 ~/.ccquick/202604061120-slug/
后台启动 claude-code session
    ↓
indicator 显示活跃状态（动画）
用户可点开查看"正在执行的任务列表"
    ↓
任务完成
    ↓
系统通知推送 + indicator badge +1
    ↓
用户点开 indicator → 查看结果 → badge 清零
```

---

## UI 组件

### 1. 菜单栏 Indicator（NSStatusItem）

**状态变化：**

| 状态 | 图标表现 |
|------|---------|
| 空闲，无待查看 | 默认图标 |
| 有任务执行中 | 图标动画（旋转或脉冲） |
| 有已完成待查看 | 图标 + 动态绘制数字徽标（如 `⚡3`） |
| 执行中 + 有待查看 | 动画 + 数字同时显示 |

数字徽标通过动态绘制 `NSImage` 实现（macOS tray 无原生 badge API）。

**点击展开菜单：**
```
● 正在执行 (2)
  • 帮我写一个登录页          [运行中 00:32]
  • 解释这段代码              [运行中 00:05]

● 已完成待查看 (3)
  • 写一个 README             [查看]
  • 修复登录 bug              [查看]
  • 生成测试用例              [查看]

─────────────────
  历史记录...
  退出
```

### 2. 输入框窗口（NSPanel）

- 无边框，圆角，毛玻璃背景
- 屏幕居中偏上（类 Alfred/Spotlight 位置）
- `NSWindowCollectionBehavior` 设置为跨所有 Space 显示
- `.nonactivatingPanel` 不抢占当前 App 焦点
- 失焦自动隐藏
- `ESC` 关闭

**输入框支持目录前缀：**
```
~/projects/myapp: 帮我写一个登录页
```
无前缀时使用自动创建的任务目录作为工作目录。

### 3. 任务结果查看（菜单内联展示）

点击"查看"后在菜单内展开响应文本，或弹出一个小型只读文本窗口（NSPanel）。
具体形式待定，优先做菜单内展开。

### 4. 历史记录窗口

独立窗口，列表展示所有历史任务，可搜索、可查看详情。

---

## 数据存储

### 目录结构

```
~/.ccquick/
├── 202604061120-write-login-page/
│   ├── meta.json
│   └── (claude 产出的文件，如有)
├── 202604061133-fix-readme/
│   ├── meta.json
│   └── ...
└── ...
```

### meta.json 结构

```json
{
  "id": "202604061120-write-login-page",
  "prompt": "帮我写一个登录页",
  "workDir": "/Users/jiechen/.ccquick/202604061120-write-login-page",
  "status": "completed",
  "startedAt": "2026-04-06T11:20:00Z",
  "finishedAt": "2026-04-06T11:21:30Z",
  "response": "claude 的完整输出文本...",
  "viewed": false
}
```

**status 枚举：** `running` | `completed` | `failed`

### Slug 生成规则

取指令前 30 个字符，转小写，空格替换为 `-`，去除特殊字符：
- `"帮我写一个登录页"` → `202604061120-帮我写一个登录页`
- `"fix the login bug in auth.ts"` → `202604061120-fix-the-login-bug-in-auth`

---

## Claude Code 调用

### 命令

```bash
claude --dangerously-skip-permissions -p "<用户指令>"
```

在对应任务目录下执行，claude 自动 trust 当前工作目录。

### Swift 调用方式

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/local/bin/claude")
process.arguments = ["--dangerously-skip-permissions", "-p", prompt]
process.currentDirectoryURL = taskDir

let pipe = Pipe()
process.standardOutput = pipe
process.standardError = pipe

// 异步读取 stdout（streaming）
pipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    // 追加到响应缓冲
}

process.terminationHandler = { _ in
    // 任务完成，更新 meta.json，发送通知
}

process.launch()
```

### claude CLI 路径探测

启动时检测以下路径，找到第一个可用的：
- `/usr/local/bin/claude`
- `/opt/homebrew/bin/claude`
- `~/.local/bin/claude`
- `which claude` 动态查找

---

## 通知

使用 `UNUserNotificationCenter`：

```
标题：CCQuick ✓
内容：帮我写一个登录页
操作：查看结果
```

点击通知 → 打开对应任务结果。

---

## 技术栈

| 层 | 选型 |
|----|------|
| 语言 | Swift 5.9+ |
| UI | SwiftUI + AppKit（NSStatusItem、NSPanel） |
| 并发 | Swift Concurrency（async/await） |
| 存储 | 文件系统（meta.json） |
| 通知 | UserNotifications framework |
| 打包 | Xcode，支持 notarization |

---

## 非功能要求

- **无 Dock 图标**：`Info.plist` 设置 `LSUIElement = true`
- **开机自启**：使用 `SMAppService.mainApp.register()`（macOS 13+）
- **目录清理**：提供设置，默认保留最近 100 条历史，可手动清理
- **权限**：首次启动申请通知权限；辅助功能权限（全局快捷键需要）

---

## 里程碑

| 阶段 | 内容 |
|------|------|
| M1 | 菜单栏图标 + 全局快捷键 + 输入框窗口 |
| M2 | claude 调用 + 任务目录创建 + stdout 捕获 |
| M3 | 系统通知 + indicator 状态/badge |
| M4 | 任务列表（菜单展开） + 结果查看 |
| M5 | 历史记录窗口 + 搜索 |
| M6 | 开机自启 + 目录清理 + 设置页 |
