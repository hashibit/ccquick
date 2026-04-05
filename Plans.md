# CCQuick — Plans.md

## 状態凡例
- `cc:TODO` — 未着手
- `cc:WIP` — 作業中
- `cc:DONE` — 完了

---

## M1 — 基础骨架

### 目标
菜单栏图标 + 全局快捷键 + 输入框窗口

### 任务

- [ ] `cc:TODO` **创建 Xcode 项目**
  - 新建 macOS App（SwiftUI）
  - 设置 `LSUIElement = true`（无 Dock 图标）
  - 配置 App Sandbox / Hardened Runtime

- [ ] `cc:TODO` **菜单栏图标（NSStatusItem）**
  - 创建 `StatusItemController`
  - 实现基础图标显示
  - 点击展开菜单（含"退出"）

- [ ] `cc:TODO` **全局快捷键**
  - 申请 Accessibility 权限
  - 注册 `NSEvent.addGlobalMonitorForEvents`
  - 默认快捷键：`⌘⇧Space`（可配置）

- [ ] `cc:TODO` **输入框窗口（NSPanel）**
  - 无边框圆角毛玻璃风格
  - 屏幕居中偏上（类 Alfred）
  - 跨 Space 显示（`NSWindowCollectionBehavior`）
  - 失焦自动隐藏，ESC 关闭

---

## M2 — Claude 调用

### 目标
后台执行 claude，捕获输出，写入 meta.json

### 任务

- [ ] `cc:TODO` **Claude CLI 路径探测**
  - 检测 `/usr/local/bin/claude`、`/opt/homebrew/bin/claude` 等
  - 找不到时提示用户

- [ ] `cc:TODO` **任务目录创建**
  - 格式：`~/.ccquick/YYYYMMDDHHM-slug/`
  - Slug 由指令前30字符生成

- [ ] `cc:TODO` **TaskRunner（Process + Pipe）**
  - 非交互模式：`claude --dangerously-skip-permissions -p "<prompt>"`
  - 异步捕获 stdout streaming
  - terminationHandler 更新任务状态

- [ ] `cc:TODO` **TaskStore（meta.json R/W）**
  - 写入 `status`、`prompt`、`response`、时间戳
  - `viewed` 字段管理 badge 计数

---

## M3 — 通知与 Indicator 状态

### 目标
任务完成后推送通知，indicator 显示 badge

### 任务

- [ ] `cc:TODO` **系统通知（UNUserNotificationCenter）**
  - 首次启动申请通知权限
  - 任务完成后推送（标题 + 指令摘要）
  - 点击通知打开对应任务结果

- [ ] `cc:TODO` **Indicator 状态机**
  - 空闲 / 执行中（动画）/ 待查看（badge）
  - 动态绘制 NSImage 实现数字 badge

---

## M4 — 任务列表与结果查看

### 目标
菜单内展示任务列表，可查看结果

### 任务

- [ ] `cc:TODO` **菜单内任务列表**
  - "正在执行" 分组（含耗时）
  - "已完成待查看" 分组

- [ ] `cc:TODO` **结果查看**
  - 点击任务 → 弹出只读文本窗口（NSPanel）
  - 查看后 `viewed = true`，badge -1

---

## M5 — 历史记录

### 目标
独立历史窗口，支持搜索

### 任务

- [ ] `cc:TODO` **历史记录窗口**
  - 读取 `~/.ccquick/` 目录列表
  - 按时间倒序展示
  - 可搜索指令内容
  - 点击查看完整响应

---

## M6 — 完善

### 目标
开机自启、设置、目录清理

### 任务

- [ ] `cc:TODO` **开机自启**（`SMAppService`，macOS 13+）

- [ ] `cc:TODO` **设置页**
  - 自定义快捷键
  - Claude CLI 路径
  - 历史保留数量（默认 100 条）

- [ ] `cc:TODO` **目录清理**
  - 超出保留数量时自动删除最旧的

---

## 已完成

（暂无）
