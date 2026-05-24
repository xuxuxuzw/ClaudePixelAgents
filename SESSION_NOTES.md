# ClaudePixelAgents 完整开发会话记录

## 一、项目概述

创建一个原生 macOS 应用「ClaudePixelAgents」，将 Claude Code 代理显示为像素风格的动画角色，场景是一个虚拟办公室。结合 ClaudeGUI 的 CLI 集成模式和 pixel-agents 的 React/Canvas 渲染，通过 WKWebView 嵌入。

**架构决策**：SwiftUI 壳 + WKWebView，纯像素办公室界面（无终端），仅 JSONL 轮询（无 hooks）。

**参考项目**：
- `/Users/xuzhaowen/code/my/pixel-agents` — VS Code 扩展，像素办公室 React/Canvas 渲染
- `/Users/xuzhaowen/Documents/xiaomimimo_used/ClaudeGUI` — 已有的 ClaudeGUI Mac 应用

---

## 二、快速启动

### 环境要求
- macOS 14.0+
- Swift 5.9+
- 正在运行的 Claude Code 会话（用于自动发现 Agent）

### 启动命令

```bash
# 进入项目目录
cd /Users/xuzhaowen/Documents/xiaomimimo_used/ClaudePixelAgents

# 编译并运行
swift run
```

应用启动后：
1. 自动启动本地 HTTP 服务器（端口随机）
2. 加载像素办公室界面
3. 轮询并发现正在运行的 Claude 会话
4. 为每个会话创建对应的像素角色（随机中文名字 + 随机岗位）
5. 角色状态根据实际会话活动实时更新

### 查看日志

```bash
# 查看应用日志
log show --predicate 'process == "ClaudePixelAgents"' --last 10m

# 查看 Agent 轮询状态
log show --predicate 'process == "ClaudePixelAgents" AND eventMessage CONTAINS "AgentTracker"' --last 5m
```

---

## 三、用户需求（按时间顺序）

1. "学习 pixel-agents 的 AI 代理构建真实事物的游戏界面，我想自己做一个 Mac 应用"
2. 选择方案：Swift + WebView（推荐）→ 纯像素办公室游戏界面，不做终端 → 仅 JSONL 轮询
3. "要注意中英文语言切换功能，然后要分别列几十个中文和英文的名字给 Agent 们随机起个名字"
4. "为什么计划内容不是写在 ClaudePixelAgents 目录下" → 将计划复制到项目根目录
5. "支持发现新增 Agent 后，自动增加工位"
6. "然后要列一些岗位，随机分配"
7. "要有入职和离职记录"
8. "办公室要根据时间，有白天和黑夜的切换，黑夜的话就是稍微暗一点而已"
9. "如果参照真实的办公室，你觉得还可以补充些什么" → 建议补充工位名牌、喝咖啡/摸鱼行为、环境音效、欢迎横幅
10. "好呀"（同意补充上述功能）
11. "开始干"
12. "再启动一下"
13. "一片空白"（白屏问题）
14. "只是个游戏界面的应用，不需要有增加 Agent 这样的终端能力" → 移除 launchAgent/closeAgent
15. "说好的中英文切换也没实现" → 添加工具栏语言切换按钮 + agentTeamInfo 消息
16. "人物被一些素材挡住" / "只看到游戏人物，没看到工位" → 待排查
17. "中文名字下有个 Idle" → 发送初始 agentStatus(waiting) 消息

---

## 四、项目结构

```
ClaudePixelAgents/
├── Package.swift                              # SPM 配置
├── PLAN.md                                    # 中文实施计划
├── SESSION_NOTES.md                           # 本文件
├── WHITE_SCREEN_FIX.md                        # 白屏问题排查与修复记录
├── Sources/ClaudePixelAgents/
│   ├── PixelAgentsApp.swift                   # @main SwiftUI 应用入口 + 语言切换工具栏按钮
│   ├── ContentView.swift                      # NSViewRepresentable 包装 WKWebView（单例模式）
│   ├── WebViewBridge.swift                    # 核心桥接：LocalServer + acquireVsCodeApi shim + 消息路由（单例）
│   ├── AssetLoader.swift                      # CoreGraphics PNG 解码 + 资源加载序列
│   ├── AgentTracker.swift                     # 后台线程轮询 `claude agents --json`，管理 agent 生命周期
│   ├── TranscriptWatcher.swift                # 每个 agent 的 JSONL 文件轮询 (500ms)
│   ├── TranscriptParser.swift                 # JSONL 记录解析 -> ServerMessage 类型
│   ├── AgentState.swift                       # Agent 状态模型
│   ├── AgentNames.swift                       # 30 中文 + 30 英文随机名字
│   ├── AgentRoles.swift                       # 25 中文 + 25 英文岗位
│   ├── EmploymentLog.swift                    # 入职/离职记录持久化
│   ├── Localization.swift                     # 中英文切换 (L10n 枚举)
│   ├── DayNightCycle.swift                    # 昼夜切换（系统时间 → brightness）
│   ├── CoffeeBreak.swift                      # 空闲 30s 后 30% 概率触发摸鱼行为
│   ├── AmbientSound.swift                     # NSSound 环境音效
│   ├── LocalServer.swift                      # Python http.server 本地服务器（提供 webview 资源）
│   └── webview/                               # 从 pixel-agents/dist/webview/ 拷贝
│       ├── index.html
│       └── assets/
│           ├── index-BLWBXxvU.js              # React 打包后的 JS bundle
│           ├── index-Q2fe2iQi.css
│           ├── characters/                    # char_0.png ~ char_5.png (112x96 each)
│           ├── floors/                        # floor_0.png ~ floor_8.png (16x16 each)
│           ├── walls/                         # wall_0.png (64x128 → 16 个 bitmask)
│           ├── furniture/                     # 25+ 个家具 PNG
│           ├── furniture-catalog.json         # 家具目录
│           ├── default-layout-1.json          # 默认布局
│           └── fonts/                         # 像素字体
```

---

## 五、各文件详细内容与功能

### 4.1 Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ClaudePixelAgents",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudePixelAgents",
            path: "Sources/ClaudePixelAgents",
            resources: [.copy("webview")],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
            ]
        ),
    ]
)
```

- macOS 14+ 目标
- 无外部依赖
- `.copy("webview")` 将 webview 前端资源打包到 resource bundle
- 链接 WebKit、CoreGraphics、ImageIO 框架

### 4.2 PixelAgentsApp.swift

```swift
import SwiftUI

@main
struct PixelAgentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1200, height: 800)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
```

- 隐藏标题栏，统一工具栏样式
- 默认窗口 1200x800
- 关闭最后一个窗口时退出应用

### 4.3 ContentView.swift

```swift
import SwiftUI
import WebKit

struct ContentView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let bridge = WebViewBridge.shared  // 使用单例
        context.coordinator.bridge = bridge
        return bridge.webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var bridge: WebViewBridge? }
}
```

- NSViewRepresentable 包装 WKWebView
- Coordinator 持有 WebViewBridge 引用，防止被释放
- **使用 `WebViewBridge.shared` 单例**，避免 SwiftUI 多次调用 `makeNSView` 创建多个实例

### 4.4 WebViewBridge.swift（核心桥接）

**当前状态（单例 + LocalServer HTTP 加载）：**

```swift
import WebKit

class WebViewBridge: NSObject {
    private static var _shared: WebViewBridge?
    static var shared: WebViewBridge {
        if _shared == nil { _shared = WebViewBridge() }
        return _shared!
    }

    let webView: WKWebView
    private let userContentController: WKUserContentController
    private var assetLoader: AgentAssetLoader?
    private var agentTracker: AgentTracker?
    private var dayNightCycle: DayNightCycle?
    private var localServer: LocalServer?

    override init() {
        userContentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        userContentController.add(self, name: "claudePixelAgents")
        webView.navigationDelegate = self

        // 通过 WKUserScript 注入 acquireVsCodeApi 垫片
        let shimSource = """
        window.acquireVsCodeApi = function() {
            return {
                postMessage: function(msg) {
                    window.webkit.messageHandlers.claudePixelAgents.postMessage(JSON.stringify(msg));
                }
            };
        };
        """
        let userScript = WKUserScript(source: shimSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        userContentController.addUserScript(userScript)

        assetLoader = AgentAssetLoader(bridge: self)
        agentTracker = AgentTracker(bridge: self)
        dayNightCycle = DayNightCycle(bridge: self)
        startServerAndLoad()
    }

    private func startServerAndLoad() {
        guard let server = LocalServer() else { return }
        self.localServer = server
        server.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.loadFromServer(port: server.actualPort)
        }
    }

    private func loadFromServer(port: UInt16) {
        guard let url = URL(string: "http://localhost:\(port)/index.html") else { return }
        webView.load(URLRequest(url: url))
    }

    func sendToWebview(_ message: [String: Any]) { ... }
    func sendToWebviewRaw(_ jsonString: String) { ... }
}
```

**为什么用单例：** SwiftUI 的 `NSViewRepresentable` 会多次调用 `makeNSView`，如果每次 `init()` 都创建新实例，会导致多个 HTTP 服务器进程和多个 AgentTracker。

**为什么用 LocalServer：** WKWebView 无法通过 `file://` 协议加载 ES module（`<script type="module">`），详见第六节白屏问题排查。

**消息路由（WKScriptMessageHandler）：**
- `webviewReady` → 触发资源加载 + agent 追踪 + 昼夜循环
- `saveLayout` → 保存到 `~/.pixel-agents/layout.json`
- `saveAgentSeats` → 保存到 `~/.pixel-agents/agent-seats.json`
- `setLanguage` → 切换语言并发送 `languageLoaded` 消息

**WKNavigationDelegate：**
```swift
func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    NSLog("[WebViewBridge] Page loaded")
}
```

**资源包查找逻辑（已废弃）：**
原使用 `findResourceBundle()` 遍历 `Bundle.allBundles`，现改为 `LocalServer` 从 `Bundle.main.resourceURL` 提供 HTTP 服务。

### 4.5 AssetLoader.swift

CoreGraphics PNG 解码器 + 资源加载序列。

**PNG 解码流程：**
1. `CGImageSourceCreateWithData` → `CGImage`
2. `CGContext` 创建 RGBA 位图上下文
3. `context.draw(cgImage)` → 提取像素数据
4. 遍历像素，转为 `#RRGGBBAA` 十六进制字符串数组

**资源加载序列（按顺序）：**
1. `characterSpritesLoaded` — 6 个角色 PNG (112x96) → 3 方向 × 7 帧 × 16x32 像素
2. `floorTilesLoaded` — 9 个地板 PNG (16x16)
3. `wallTilesLoaded` — 1 个墙壁 PNG (64x128) → 16 个 bitmask 片段
4. `furnitureAssetsLoaded` — 家具目录 JSON + 25+ 个家具 PNG
5. `layoutLoaded` — 默认布局 JSON（优先读取 `~/.pixel-agents/layout.json`）
6. `settingsLoaded` — 应用设置

**sliceRegion 函数：** 从解码后的像素数据中裁剪指定区域，返回 `[[String]]`（每行每像素一个 hex 字符串）。

### 4.6 AgentTracker.swift

**核心功能：**
- 每 5 秒轮询 `claude agents --json`（通过 `/bin/zsh -l -c` 执行，**在后台线程**）
- 发现新 background session → 分配随机名字 + 岗位 → 记录入职 → 发送 `agentCreated` + `agentTeamInfo` + `agentStatus(waiting)`
- session 消失 → 记录离职 → 发送 `agentClosed`
- 为每个 agent 启动 `TranscriptWatcher` 监听 JSONL 文件

**为什么在后台线程轮询：** `Process.waitUntilExit()` 会阻塞当前线程。如果在主线程执行，会导致后续轮询无法执行，新增的 agent 不会被发现。

**Claude CLI 路径查找：**
- 扫描 `~/.nvm/versions/node/*/bin/claude`（最新版本优先）
- 回退到系统 `claude`

**JSONL 文件路径计算：**
- `~/.claude/projects/<projectHash>/<sessionId>.jsonl`
- projectHash = `path.replacingOccurrences(of: ":", "-").replacingOccurrences(of: "/", "-")`

**Agent 状态管理：**
- `knownSessions: [String: Int]` — sessionId → agentId 映射
- `agentStates: [Int: AgentState]` — agentId → 状态对象
- `watchers: [Int: TranscriptWatcher]` — agentId → JSONL 监听器

### 4.7 TranscriptWatcher.swift

- 每 500ms 轮询 JSONL 文件的新内容
- 启动时 `seekToEndOfFile()` 跳到文件末尾（只监听新内容）
- 读取新字节 → 拼接到行缓冲区 → 按换行分割 → 逐行传给 `TranscriptParser`
- 最大单次读取 64KB

### 4.8 TranscriptParser.swift

**JSONL 记录解析逻辑：**

| 角色 | 条件 | 生成的消息 |
|------|------|-----------|
| `assistant` + `tool_use` | 工具开始使用 | `agentToolStart` + `agentStatus(active)` |
| `user` + `tool_result` | 工具结果返回 | `agentToolDone` |
| `user` + 纯文本 | 用户输入新指令 | `agentToolsClear` + 清除活动状态 |
| `system` + `turn_duration` | 回合结束 | `agentToolsClear` + `agentStatus(waiting)` |

**启发式定时器：**
- 权限等待定时器 (7s)：非豁免工具使用超过 7 秒未完成 → 发送 `agentToolPermission`
- 文字空闲定时器 (5s)：assistant 回复中无 tool_use → 5 秒后清除活动状态
- 权限豁免工具：Read, Glob, Grep, WebFetch, WebSearch, LS

**工具状态格式化：**
- Read → "Reading filename"
- Write → "Writing filename"
- Edit → "Editing filename"
- Bash → "Running command..."（截断到 40 字符）
- Glob → "Searching files"
- Grep → "Searching code"
- Agent/Task → "Subtask: description"

### 4.9 AgentNames.swift

```swift
enum AgentNames {
    private static let chineseNames = [
        "小青", "墨竹", "星河", "云起", "知秋", "若水", "清风", "明月",
        "松间", "石韵", "灵犀", "拾光", "逐梦", "归燕", "听雨", "踏雪",
        "浮云", "流萤", "破晓", "凌霄", "微澜", "深蓝", "赤焰", "翠微",
        "白露", "暮色", "晨曦", "远山", "幽兰", "素心",
    ]
    private static let englishNames = [
        "Ada", "Bolt", "Cipher", "Dash", "Echo", "Flux", "Glimmer", "Haze",
        "Iris", "Jet", "Kite", "Luna", "Milo", "Nova", "Onyx", "Pixel",
        "Quill", "Rune", "Spark", "Terra", "Ursa", "Vex", "Wren", "Xeno",
        "Yara", "Zephyr", "Archer", "Blaze", "Coral", "Drift",
    ]
    static func randomName(for language: Language) -> String { ... }
}
```

### 4.10 AgentRoles.swift

```swift
enum AgentRoles {
    private static let chineseRoles = [
        "前端工程师", "后端工程师", "全栈工程师", "产品经理", "UI 设计师",
        "测试工程师", "数据工程师", "运维工程师", "架构师", "算法工程师",
        "安全工程师", "数据库管理员", "技术总监", "项目经理", "DevOps 工程师",
        "移动端开发", "嵌入式开发", "游戏开发", "AI 训练师", "技术作家",
        "代码审查员", "性能优化师", "系统分析师", "解决方案架构师", "技术顾问",
    ]
    private static let englishRoles = [
        "Frontend Engineer", "Backend Engineer", "Full Stack Engineer",
        "Product Manager", "UI Designer", "QA Engineer", "Data Engineer",
        "DevOps Engineer", "Architect", "ML Engineer", "Security Engineer",
        "DBA", "Tech Lead", "Project Manager", "Mobile Developer",
        "Embedded Developer", "Game Developer", "AI Trainer", "Tech Writer",
        "Code Reviewer", "Performance Engineer", "Systems Analyst",
        "Solution Architect", "Tech Consultant", "SRE",
    ]
    static func randomRole(for language: Language) -> String { ... }
}
```

### 4.11 EmploymentLog.swift

```swift
struct EmploymentRecord: Codable {
    let time: Date
    let name: String
    let role: String
    let event: EventType  // .hire / .fire
}

class EmploymentLog {
    private var records: [EmploymentRecord] = []
    private let filePath: String  // ~/.pixel-agents/employment-log.json

    func recordHire(name: String, role: String) { ... }
    func recordFire(name: String, role: String) { ... }
    func getAllRecords() -> [EmploymentRecord] { ... }
}
```

- 入职/离职时自动记录
- 持久化到 `~/.pixel-agents/employment-log.json`
- 启动时加载历史记录

### 4.12 Localization.swift

```swift
enum Language: String {
    case chinese = "zh"
    case english = "en"
}

class Localization {
    static let shared = Localization()
    var currentLanguage: Language  // UserDefaults 持久化

    var working: String       // "工作中" / "Working"
    var waiting: String       // "等待中" / "Waiting"
    var permissionNeeded: String  // "需要许可" / "Permission needed"
    var reading: String       // "正在读取" / "Reading"
    var writing: String       // "正在写入" / "Writing"
    var editing: String       // "正在编辑" / "Editing"
    var hired: String         // "入职" / "Hired"
    var fired: String         // "离职" / "Fired"
    func welcomeBanner(name: String) -> String  // "欢迎 XXX 加入团队！" / "Welcome XXX to the team!"
    var windowTitle: String   // "Claude 像素办公室" / "Claude Pixel Office"
}
```

### 4.13 DayNightCycle.swift

```swift
class DayNightCycle {
    private weak var bridge: WebViewBridge?
    private var timer: Timer?

    func start() {
        updateBrightness()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { ... }
    }

    private func calculateBrightness() -> Double {
        // 6:00-8:00 黎明: 0.7 → 1.0
        // 8:00-18:00 白天: 1.0
        // 18:00-20:00 黄昏: 1.0 → 0.7
        // 20:00-6:00 夜晚: 0.7
    }
}
```

- 每 5 分钟检查系统时间
- 发送 `dayNightUpdate` 消息（含 brightness 值）到 webview
- webview 在 Canvas 上叠加半透明黑色遮罩（opacity = 1.0 - brightness）

### 4.14 CoffeeBreak.swift

```swift
class CoffeeBreak {
    static let shared = CoffeeBreak()
    private let breakChance = 0.3       // 30% 概率
    private let idleThreshold: TimeInterval = 30.0  // 空闲 30 秒后检查
    private let breakDuration: TimeInterval = 20.0  // 喝咖啡持续 20 秒

    func scheduleBreakCheck(agentId: Int, bridge: WebViewBridge?) { ... }
    func cancelBreakCheck(agentId: Int) { ... }
}
```

- agent 空闲 30 秒后，每秒检查一次是否触发摸鱼
- 30% 概率触发：发送 `coffeeBreakStart` → 20 秒后发送 `coffeeBreakEnd`

### 4.15 AmbientSound.swift

```swift
class AmbientSound {
    static let shared = AmbientSound()
    var isEnabled: Bool  // UserDefaults 持久化

    func playTypingSound()     // NSSound(named: "key_press_click")
    func playDoneSound()       // NSSound(named: "Glass")
    func playPermissionSound() // NSSound(named: "Ping")
}
```

### 4.16 LocalServer.swift（本地 HTTP 服务器）

基于 Python `http.server` 的本地 HTTP 服务器，用于通过 HTTP 协议加载 webview 资源。

```swift
class LocalServer {
    private var process: Process?
    private(set) var actualPort: UInt16 = 0
    private let webviewDir: String

    init?() {
        // 在 Bundle 中查找 webview 目录
        let bundle = Bundle.main
        guard let resourceURL = bundle.resourceURL else { return nil }
        webviewDir = resourceURL.appendingPathComponent("webview").path
        guard FileManager.default.fileExists(atPath: webviewDir) else { return nil }
    }

    func start() {
        let port = findFreePort()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["-m", "http.server", "\(port)", "--bind", "127.0.0.1", "--directory", webviewDir]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        self.process = task
        self.actualPort = UInt16(port)
    }

    func stop() { process?.terminate() }

    private func findFreePort() -> Int {
        // 用 Python socket 绑定端口 0 获取空闲端口
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["-c", """
            import socket
            s = socket.socket()
            s.bind(('', 0))
            print(s.getsockname()[1])
            s.close()
            """]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return Int(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "8080") ?? 8080
    }
}
```

**演进历史：**
1. 最初尝试 `NWListener`（Network.framework）→ `localPort` 属性不存在，放弃
2. 改用 Python `http.server` → 稳定运行

---

## 六、关键架构：传输桥接原理

### 核心技巧

通过 WKWebView 的 user script 注入 `acquireVsCodeApi()` 垫片，让 webview 的 React 应用以为自己运行在 VS Code 中。

### 消息流

```
webview (React)                     Swift (WKWebView)
     |                                    |
     |  acquireVsCodeApi().postMessage()  |
     |  → window.webkit.messageHandlers   |
     |     .claudePixelAgents             |
     |     .postMessage(JSON)             |
     |  ───────────────────────────────→  |
     |                                    |  WKScriptMessageHandler
     |                                    |  .userContentController(_:didReceive:)
     |                                    |
     |  window.addEventListener('message')|
     |  ← window.postMessage(JSON)       |
     |  ← evaluateJavaScript(...)        |
     |  ───────────────────────────────←  |
```

### Webview 端 JS 代码（关键部分）

`pixel-agents/webview-ui/src/transport/postMessageTransport.ts`：
```typescript
export class PostMessageTransport implements MessageTransport {
  private readonly vscodeApi: { postMessage(msg: unknown): void };
  constructor() {
    this.vscodeApi = acquireVsCodeApi();  // 需要 shim 提供
  }
  send(message: ClientMessage): void {
    this.vscodeApi.postMessage(message);
  }
  onMessage(handler: (message: ServerMessage) => void): () => void {
    const listener = (e: MessageEvent) => handler(e.data as ServerMessage);
    window.addEventListener('message', listener);
    return () => window.removeEventListener('message', listener);
  }
}
```

`pixel-agents/webview-ui/src/runtime.ts`：
```typescript
declare function acquireVsCodeApi(): unknown;
type Runtime = 'vscode' | 'browser';
const runtime: Runtime = typeof acquireVsCodeApi !== 'undefined' ? 'vscode' : 'browser';
export const isBrowserRuntime = runtime === 'browser';
```

`pixel-agents/webview-ui/src/transport/index.ts`：
```typescript
function createTransport(): MessageTransport {
  if (!isBrowserRuntime) {
    return new PostMessageTransport();  // vscode 模式
  }
  // browser 模式使用 WebSocket
  const ws = new WebSocketTransport(wsUrl);
  ws.connect();
  return ws;
}
export const transport: MessageTransport = createTransport();
```

`pixel-agents/webview-ui/src/hooks/useExtensionMessages.ts`（第 516 行）：
```typescript
transport.send({ type: 'webviewReady' });  // React 组件挂载后发送
```

### 关键时序

1. `WKUserScript(atDocumentStart:)` 注入 `acquireVsCodeApi` shim（在任何脚本执行前）
2. HTTP 服务器加载 HTML → ES module 加载
3. `runtime.ts` 检查 `typeof acquireVsCodeApi` → `'vscode'`
4. `transport/index.ts` 创建 `PostMessageTransport` → 调用 `acquireVsCodeApi()`
5. React 组件挂载 → `useExtensionMessages` 发送 `webviewReady`
6. Swift 收到 `webviewReady` → 启动资源加载 + agent 追踪

---

## 七、白屏问题详细排查记录

### 症状
- 应用构建成功，运行正常
- 资源包找到，index.html 加载成功
- `"[WebViewBridge] Page loaded"` 日志输出
- 但 webview 显示空白，不显示像素办公室

### 已确认的事实

1. **资源包已找到**：
   ```
   [AssetLoader] Found bundle at: .build/debug/ClaudePixelAgents_ClaudePixelAgents.bundle
   [WebViewBridge] Found bundle: /Users/.../ClaudePixelAgents_ClaudePixelAgents.bundle
   ```

2. **index.html 已加载**：
   ```
   [WebViewBridge] Loading from: .../webview/index.html
   [WebViewBridge] Read access to: .../webview
   [WebViewBridge] Page loaded
   ```

3. **acquireVsCodeApi shim 已成功注入**（JS probe 确认）：
   ```
   [WebViewBridge] JS probe result: {"acquireVsCodeApi":"function","messageHandlers":true}
   ```
   - `acquireVsCodeApi` 是 `"function"` — shim 已注入且可用
   - `messageHandlers` 是 `true` — `window.webkit.messageHandlers.claudePixelAgents` 存在

4. **但 webviewReady 消息未收到**：Swift 端 `WKScriptMessageHandler` 未收到任何来自 webview 的消息

### 尝试过的方案

| # | 方案 | 结果 |
|---|------|------|
| 1 | `loadFileURL` + `WKUserScript` atDocumentStart | 白屏，shim 时序问题 |
| 2 | `loadHTMLString` + baseURL（无 shim 注入） | 白屏 |
| 3 | `loadHTMLString` + HTML 内容注入 shim（在 `<script>` 标签前插入） | 白屏，但 JS probe 确认 shim 已注入 |
| 4 | 同时使用 HTML 注入 + WKUserScript | 白屏，shim 确认注入但 React 未发送 webviewReady |
| 5 | 在 `didFinish` 中 `evaluateJavaScript` 测试消息通道 | 未完成测试（用户中断） |

### 当前 WebViewBridge.swift 状态

同时使用两种注入方式：
1. **HTML 字符串注入**：在 `loadHTMLString` 前，将 `<script>` shim 插入到 HTML 的第一个 `<script>` 标签前
2. **WKUserScript 备份**：`atDocumentStart` 注入，作为备份

`loadWebApp()` 使用 `loadHTMLString(htmlContent, baseURL: webviewDir)`，baseURL 指向 bundle 中的 webview 目录。

### 可能的根因分析

shim 已注入且 `acquireVsCodeApi` 是 function，但 React 应用没有发送 `webviewReady`。可能原因：

1. **React 组件未挂载**：`loadHTMLString` 可能导致子资源（JS/CSS）加载失败，React 应用未初始化
   - `loadHTMLString` 与 `loadFileURL` 的区别：前者创建 synthetic document，后者是真实的 file:// document
   - 即使设置了 baseURL，子资源加载可能受跨域限制

2. **Transport 创建时序问题**：模块加载时 `acquireVsCodeApi` 可能还没定义
   - 虽然 shim 在 HTML 中，但 ES module 可能在 shim 执行前就被解析
   - WKWebView 对 `<script type="module">` 的执行顺序可能与普通 `<script>` 不同

3. **webviewReady 已发送但未收到**：消息编码/解码问题
   - `postMessage(JSON.stringify(msg))` 中 JSON 字符串可能包含特殊字符导致解析失败
   - Swift 端 `JSONSerialization.jsonObject` 可能无法解析某些消息

4. **React 应用加载但出错**：JS bundle 执行过程中有错误
   - 可能缺少某些全局变量或 polyfill
   - 可能某些 import 路径在 `loadHTMLString` 模式下无法解析

### 建议的下一步排查方向

1. **测试消息通道**：在 `didFinish` 中直接调用 `window.webkit.messageHandlers.claudePixelAgents.postMessage()`，确认 Swift 端能收到
   ```swift
   webView.evaluateJavaScript("""
       window.webkit.messageHandlers.claudePixelAgents.postMessage(
           JSON.stringify({type: 'testPing'})
       )
   """) { result, error in
       print("Test ping: \(result ?? "nil") error: \(error?.localizedDescription ?? "none")")
   }
   ```

2. **如果 ping 成功** → 问题是 React 应用未发送 `webviewReady`
   - 检查 React bundle 是否加载成功（检查网络请求或 evaluateJavaScript 检查 DOM）
   - 尝试用 `loadFileURL` 代替 `loadHTMLString`，将 shim 写入磁盘上的 HTML 副本

3. **如果 ping 失败** → 问题是消息通道本身
   - 检查 `WKScriptMessageHandler` 是否正确注册
   - 检查消息格式是否正确

4. **终极方案：不依赖 acquireVsCodeApi**
   - 创建自定义 transport，直接通过 `window.addEventListener('message')` 接收消息
   - 修改 JS bundle 或注入自定义模块覆盖 transport 创建逻辑

### 最终解决方案

**根本原因：WKWebView 无法通过 `file://` 协议加载 ES module 脚本。**

index.html 中的 React 打包产物使用了 `<script type="module">` 标签：
```html
<script type="module" crossorigin src="./assets/index-BLWBXxvU.js"></script>
```

无论使用 `loadHTMLString(baseURL:)` 还是 `loadFileURL(allowingReadAccessTo:)`，WKWebView 都无法正确执行这个模块脚本：

| 加载方式 | 结果 | 原因 |
|---------|------|------|
| `loadHTMLString` + `baseURL` | 白屏 | synthetic document，模块加载器拒绝相对导入 |
| `loadFileURL` + `allowingReadAccessTo` | 白屏 | `crossorigin` 属性触发 CORS 检查，`file://` 协议无法通过 |

**解决方法：启动本地 HTTP 服务器，通过 `http://localhost:<port>` 提供 webview 资源。**

1. 创建 `LocalServer.swift`，使用 Python `http.server` 模块
2. 先用 `socket.bind(('', 0))` 获取空闲端口
3. 启动 `python3 -m http.server <port> --bind 127.0.0.1 --directory <webviewDir>`
4. WebViewBridge 通过 `http://localhost:<port>/index.html` 加载页面
5. ES module 在 `http://` 协议下正常加载
6. `acquireVsCodeApi` shim 通过 `WKUserScript(atDocumentStart:)` 注入，在 ES module 执行前绑定

**同时修复的其他问题：**
- **SwiftUI 重复创建实例**：改为单例模式（`private static var _shared` + computed `shared`），在 `PixelAgentsApp.init()` 中预初始化
- **Agent 轮询阻塞主线程**：`Process.waitUntilExit()` 会阻塞当前线程，将 `pollAgentSessions()` 移到 `DispatchQueue.global(qos: .utility)` 执行

---

## 七（续）、其他问题修复记录

### Agent 名字显示为 "Idle"

**问题**：所有 agent 名字都显示为 "Idle" 而非中文名字。

**根因**：`AgentCreated` 消息协议没有 `name` 字段。查看 `messages.ts`：
```typescript
interface AgentCreated { type: 'agentCreated'; id: number; folderName?: string; isExternal?: boolean }
```

**解决**：创建 agent 后，额外发送 `AgentTeamInfo` 消息设置名字：
```swift
sendToWebview(["type": "agentCreated", "id": agentId])
sendToWebview(["type": "agentTeamInfo", "id": agentId, "agentName": name])  // 这行是关键
```

### Agent 名字下方显示 "Idle" 文字

**问题**：中文名字下方有 "Idle" 文字。

**根因**：创建 agent 时没有发送初始状态消息，webview 默认显示 "Idle"。

**解决**：创建 agent 后发送 `agentStatus` 消息：
```swift
sendToWebview(["type": "agentStatus", "id": agentId, "status": "waiting"])
```
`"waiting"` 对应 UI 中的本地化文字（中文"等待中"，英文"Waiting"）。

### 中英文语言切换未实现

**问题**：需求中要求支持中英文切换，但没有实现。

**解决**：
1. 在 `PixelAgentsApp.swift` 添加工具栏语言切换按钮：
```swift
ToolbarItem(placement: .automatic) {
    Button { toggleLanguage() } label: {
        Text(currentLanguage == .chinese ? "中 / EN" : "EN / 中")
    }
}
```
2. 在 `WebViewBridge.swift` 添加 `setLanguage` 消息处理和 `sendLanguageToWebview()` 方法
3. 语言偏好通过 `UserDefaults` 持久化

### 新增 Agent 在界面中不出现

**问题**：在终端新增 agent 后，游戏界面没有显示。

**根因**：`pollAgentSessions()` 中 `task.waitUntilExit()` 阻塞了主线程，导致后续轮询无法执行。

**解决**：将轮询移到后台线程：
```swift
func start() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
        self?.pollAgentSessions()
    }
    pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
        DispatchQueue.global(qos: .utility).async {
            self?.pollAgentSessions()
        }
    }
}
```

---

## 八、编译错误修复历史

1. **缺少 `import Foundation`**：AssetLoader.swift 中 `Data`、`Bundle` 找不到 → 添加 `import Foundation`
2. **类型不匹配 `AgentAssetLoader` vs `AssetLoader?`**：WebViewBridge 中属性声明为 `AssetLoader?` 但赋值 `AgentAssetLoader` → 改为 `AgentAssetLoader?`
3. **`toolId` 变量作用域**：TranscriptParser 中 `toolId` 在 `if let` 内声明但在外部使用 → 移到外部声明
4. **`AssetLoader` 协议冲突**：同时存在类 `AgentAssetLoader` 和协议 `AssetLoader` → 移除协议
5. **`resourceBundle` optional 解包**：sed 替换 `Bundle.main` 为 optional `resourceBundle` → 添加 `guard let bundle = resourceBundle`
6. **sed 破坏 AssetLoader.swift**：sed 命令破坏了类结构 → 完全重写 AssetLoader.swift
7. **`NWListener.localPort` 不存在**：LocalServer.swift 使用不存在的 API → 放弃 LocalServer 方案
8. **`WKScriptMessageLevel` 找不到**：WKNavigationDelegate 的 console 日志方法签名错误 → 移除该方法

---

## 九、构建与运行

### 快速启动（推荐）
```bash
cd /Users/xuzhaowen/Documents/xiaomimimo_used/ClaudePixelAgents
swift run
```

### 构建命令
```bash
cd /Users/xuzhaowen/Documents/xiaomimimo_used/ClaudePixelAgents
swift build
```

### 运行命令
```bash
.build/debug/ClaudePixelAgents
```

### 带日志输出运行
```bash
script -q /tmp/cpa_output.log .build/debug/ClaudePixelAgents
# 然后查看日志
cat /tmp/cpa_output.log
```

### 清理旧进程
```bash
pkill -f "ClaudePixelAgents"
```

---

## 十、外部参考文件

| 用途 | 文件路径 |
|------|---------|
| 传输协议契约 | `/Users/xuzhaowen/code/my/pixel-agents/webview-ui/src/transport/postMessageTransport.ts` |
| Transport 创建 | `/Users/xuzhaowen/code/my/pixel-agents/webview-ui/src/transport/index.ts` |
| Runtime 检测 | `/Users/xuzhaowen/code/my/pixel-agents/webview-ui/src/runtime.ts` |
| 资源加载序列 | `/Users/xuzhaowen/code/my/pixel-agents/webview-ui/src/browserMock.ts` |
| JSONL 解析逻辑 | `/Users/xuzhaowen/code/my/pixel-agents/server/src/transcriptParser.ts` |
| JSONL 文件监听 | `/Users/xuzhaowen/code/my/pixel-agents/server/src/fileWatcher.ts` |
| webviewReady 发送 | `/Users/xuzhaowen/code/my/pixel-agents/webview-ui/src/hooks/useExtensionMessages.ts` (L516) |
| 会话轮询模式 | `/Users/xuzhaowen/Documents/xiaomimimo_used/ClaudeGUI/Sources/ClaudeGUI/MainWindowController.swift` (L552-636) |
| Webview 消息处理 | `/Users/xuzhaowen/code/my/pixel-agents/webview-ui/src/hooks/useExtensionMessages.ts` |
| 本地化参考 | `/Users/xuzhaowen/Documents/xiaomimimo_used/ClaudeGUI/Sources/ClaudeGUI/Localization.swift` |
| webview index.html | `/Users/xuzhaowen/Documents/xiaomimimo_used/ClaudePixelAgents/Sources/ClaudePixelAgents/webview/index.html` |
| JS bundle | `/Users/xuzhaowen/Documents/xiaomimimo_used/ClaudePixelAgents/Sources/ClaudePixelAgents/webview/assets/index-BLWBXxvU.js` |

---

## 十一、本次会话问题修复记录

### 10.1 "Idle" 文字显示英文而非中文 "等待中"

**问题**：agent 名字下方显示 "Idle" 而非本地化的 "等待中"。

**根因**：`languageLoaded` 和 `agentCreated` 消息都通过 `DispatchQueue.main.async` 从后台线程发送，到达主线程的顺序不确定。`agentCreated` 可能先于 `languageLoaded` 到达，导致 webview 用默认英文 "Idle" 渲染。

**解决**：
1. Webview 端：`useExtensionMessages.ts` 添加 `LocalizedStrings` 接口和 `localizedStrings` 状态（localStorage 持久化，中文默认值）
2. Webview 端：`ToolOverlay.tsx` 的 `getActivityText()` 接收 `localizedStrings` 参数，用 `localizedStrings.waiting` 替代硬编码 `'Idle'`
3. Swift 端：新增 `sendLanguageToWebviewDirect()` 方法，直接调用 `evaluateJavaScript`（不经过 `DispatchQueue.main.async`），确保 `languageLoaded` 先于 `agentCreated` 到达
4. Swift 端：`AgentTracker` 在创建 agent 后立即调用 `bridge?.sendLanguageToWebviewDirect()`

### 10.2 Agent 岗位显示

**问题**：需求要求显示 agent 的岗位信息。

**解决**：
1. Webview 端：`types.ts` 的 `Character` 接口添加 `agentRole?: string`
2. Webview 端：`officeState.ts` 的 `setTeamInfo()` 接受 `agentRole` 参数
3. Webview 端：`ToolOverlay.tsx` 显示 "名字 · 岗位" 格式
4. Swift 端：`agentTeamInfo` 消息包含 `agentRole` 字段

### 10.3 窗口标题显示 agent 数量

**问题**：需求要求窗口标题显示当前 agent 数量。

**解决**：
1. `WebViewBridge.swift` 添加 `agentCount` 属性和 `onAgentCountChanged` 回调
2. `AgentTracker.swift` 的 `updateAgentCount()` 更新 `bridge?.agentCount`
3. `PixelAgentsApp.swift` 监听 `onAgentCountChanged`，更新窗口标题为 "Claude 像素办公室 — N 个代理"

### 10.4 环境音效集成

**问题**：需求要求工具操作时有音效。

**解决**：`TranscriptParser.swift` 集成 `AmbientSound.shared`：
- 工具开始 → `playTypingSound()`
- 工具完成 → `playDoneSound()`
- 权限等待 → `playPermissionSound()`

### 10.5 CoffeeBreak 生命周期集成

**问题**：摸鱼行为需要与 agent 生命周期绑定。

**解决**：`AgentTracker.swift` 在创建 agent 时调用 `CoffeeBreak.shared.scheduleBreakCheck(agentId:bridge:)`，关闭 agent 时调用 `cancelBreakCheck(agentId:)`。

### 10.6 透明像素格式不匹配（工位不显示的原因之一）

**问题**：家具 PNG 解码后的透明像素格式与 webview 不一致。

**根因**：`AssetLoader.swift` 的 `sliceRegion()` 对透明像素返回 `"#00000000"`，而 webview 的 sprite cache 用 `color === ''` 判断透明。格式不匹配导致透明像素被当作黑色像素渲染。

**解决**：`sliceRegion()` 对 alpha ≤ 2 的像素返回 `""`（空字符串），匹配 webview 的 sprite cache 期望。

### 10.7 家具资源加载失败（工位不显示的主要原因）

**问题**：家具/PNG 在 bundle 中存在，但 Swift 加载失败。

**根因**：`furniture-catalog.json` 的 `file` 字段使用扁平文件名（如 `BIN.png`），但实际 PNG 文件在子目录中（如 `furniture/BIN/BIN.png`）。部分变体文件名与目录名不匹配（如 `CUSHIONED_CHAIR_FRONT.png` 在 `furniture/CUSHIONED_CHAIR/` 目录中）。

**解决**：`loadFurniture()` 添加多级回退查找：
1. 直接查找 `webview/assets/furniture/<fileName>`
2. 回退到 `webview/assets/furniture/<id>/<fileName>`
3. 回退到逐步缩短前缀的目录（如 `CUSHIONED_CHAIR` 从 `CUSHIONED_CHAIR_FRONT` 提取）

### 10.8 消息顺序导致家具不渲染（工位不显示的核心原因）

**问题**：家具资源加载成功（38 项，0 失败），但 webview 不显示家具。

**根因**：Swift 的 `loadAllAssets()` 在后台线程执行，通过 `DispatchQueue.main.async` 将 `furnitureAssetsLoaded` 和 `layoutLoaded` 消息发送到主线程。由于两个 `async` 调用之间可能插入其他主线程工作，消息到达顺序不确定。如果 `layoutLoaded` 先到达，`layoutToFurnitureInstances()` 调用 `getCatalogEntry()` 时目录尚未构建（返回 `undefined`），所有家具被静默跳过。

**验证过程**：
1. 添加 NSLog 日志确认 Swift 端 38 项家具全部加载成功
2. 添加 WKUserScript console 拦截器，确认 webview 端收到 `furnitureAssetsLoaded` 并成功构建目录（42 assets, 7 rotation groups）
3. 确认 webview 端收到 `layoutLoaded` 并调用 `rebuildFromLayout`
4. 添加 debug 消息回传，确认 `rebuildFromLayout` 后 `furniture.length` 为 0

**解决**：`AssetLoader.swift` 的 `sendToWebview()` 从 `DispatchQueue.main.async` 改为 `DispatchQueue.main.sync`。从后台线程调用 `sync` 会阻塞后台线程直到主线程处理完消息，确保消息按发送顺序到达 webview。

**关键代码变更**：
```swift
// Before (async — order not guaranteed)
private func sendToWebview(_ message: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
        self?.bridge?.sendToWebview(message)
    }
}

// After (sync — guarantees ordering)
private func sendToWebview(_ message: [String: Any]) {
    DispatchQueue.main.sync { [weak self] in
        self?.bridge?.sendToWebview(message)
    }
}
```

### 10.9 日志捕获问题

**问题**：AssetLoader 的 `print()` 输出在 `log show` 中不显示。

**根因**：Swift 的 `print()` 输出到 stdout，而 `log show` 捕获的是系统日志（`os_log`/`NSLog`）。后台线程的 stdout 输出可能不会被系统日志收集。

**解决**：将 AssetLoader 中所有 `print()` 改为 `NSLog()`，确保日志可通过 `log show --predicate 'process == "ClaudePixelAgents"'` 捕获。

---

## 十二、待完成事项

- [x] 修复白屏问题 → 本地 HTTP 服务器方案
- [x] 菜单栏语言切换功能 → 工具栏按钮 + WebViewBridge 消息
- [x] Agent 名字显示 → AgentTeamInfo 消息
- [x] Agent 初始状态 → agentStatus(waiting) 消息
- [x] Agent 轮询不阻塞主线程 → DispatchQueue.global
- [x] "Idle" 本地化 → LocalizedStrings + sendLanguageToWebviewDirect
- [x] Agent 岗位显示 → agentRole 字段 + "名字 · 岗位" 格式
- [x] 窗口标题显示 agent 数量 → onAgentCountChanged 回调
- [x] 环境音效 → AmbientSound 集成到 TranscriptParser
- [x] CoffeeBreak 生命周期 → AgentTracker 集成
- [x] 透明像素格式 → sliceRegion 返回空字符串
- [x] 家具资源加载 → 多级回退目录查找
- [x] 消息顺序 → DispatchQueue.main.sync 保证家具先于布局到达
- [ ] 欢迎横幅功能（新 agent 入职时显示）
- [ ] 入职/离职日志面板
## 十二、下一步计划

接下来拟按优先级完成以下工作：

- 实现 `欢迎横幅`：在新 agent 入职时，在 webview 顶部短暂显示本地化欢迎横幅（可配置时长和样式）。
- 实现 `入职/离职日志面板`：在主界面或单独窗口显示历史入职/离职记录，支持筛选和导出 JSON。
- 在 webview 中实现横幅 UI：由 React 端接收 `welcomeBanner` 消息并负责动画/消失逻辑；Swift 端在 AgentTracker 记录入职后发送该消息。
- 添加测试：单元测试覆盖 `EmploymentLog` 的持久化与恢复，以及 server/webview 消息顺序的集成测试。
- 更新文档：补充 README & 使用说明，列出新增消息类型与开发调试命令。

## 十三、欢迎横幅实现草案

- 消息协议：Swift 发送 `{"type":"welcomeBanner","id":<agentId>,"name":"<agentName>","role":"<agentRole>","durationMs":3000}`。
- Webview：接收后在 `App` 顶部弹出横幅组件 `WelcomeBanner`，显示 `欢迎 {name} 加入团队！`（本地化），3s 后淡出；支持点击立即关闭。
- 可配置项：`durationMs`、是否显示头像（使用角色色块占位）、是否在欢迎横幅期间暂停其他通知。
- Edge case：当短时间内有多名 agent 入职，横幅进入队列，按到达顺序依次展示；可合并为“同时加入 3 人”等聚合文案。

## 十四、入职/离职日志面板设计草案

- 数据模型：复用 `EmploymentRecord`（已存在），在 `EmploymentLog` 中新增分页与筛选（按日期区间、事件类型、姓名、岗位）。
- 持久化文件：`~/.pixel-agents/employment-log.json`（已存在），增加导出 API `exportEmploymentLog(path)`。
- UI：在设置或工具栏添加“记录”按钮，打开 modal，展示表格、搜索框、导出按钮；支持按记录点击查看详细事件时间戳与原始 JSONL 链接（若可用）。
- 权限与隐私：记录仅保存在本地；导出时提示用户文件路径与格式。

## 十五、回归测试与验证清单

- 验证欢迎横幅在新 agent 创建后优先于 `agentCreated`/`languageLoaded` 的顺序显示本地化文案。
- 确认 `EmploymentLog` 在应用重启后能恢复历史记录并正确显示。
- 在 macOS 上测试 LocalServer 与 WKWebView 的加载，确保 `type="module"` 脚本能通过 `http://localhost` 正常加载且 `acquireVsCodeApi` shim 生效。

---

我已把以上草案追加到文档，并建立了接下来的任务清单。需要我现在实现其中某一项（例如：把 `welcomeBanner` 消息发送逻辑加到 `AgentTracker.swift` 并修改 webview React 组件接收）吗？
