# 白屏问题排查与修复记录

## 问题现象

应用构建成功、窗口正常弹出，但 WKWebView 显示一片空白，不渲染像素办公室界面。

## 根本原因

**WKWebView 无法通过 `file://` 协议加载 ES module 脚本。**

index.html 中的 React 打包产物使用了 `<script type="module">` 标签：

```html
<script type="module" crossorigin src="./assets/index-BLWBXxvU.js"></script>
```

无论使用 `loadHTMLString(baseURL:)` 还是 `loadFileURL(allowingReadAccessTo:)`，WKWebView 都无法正确执行这个模块脚本：

| 加载方式 | 结果 | 原因 |
|---------|------|------|
| `loadHTMLString` + `baseURL` | 白屏 | synthetic document，模块加载器拒绝相对导入 |
| `loadFileURL` + `allowingReadAccessTo` | 白屏 | `crossorigin` 属性触发 CORS 检查，`file://` 协议无法通过 |
| `loadFileURL` + 移除 `crossorigin` | 白屏 | WKWebView 对 bundle 内的 `file://` 模块加载有额外限制 |

**关键证据**：通过 `evaluateJavaScript` 注入诊断代码确认：
- `acquireVsCodeApi` shim 已成功注入（类型为 `function`）
- 消息通道正常（`testPing` 收发成功）
- 但 `document.getElementById('root').innerHTML` 为空 — React 从未执行

## 解决方案

启动一个本地 HTTP 服务器，通过 `http://localhost:<port>` 提供 webview 资源：

```swift
// LocalServer.swift — 使用 Python 内置 HTTP 服务器
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
task.arguments = ["-m", "http.server", "\(port)", "--bind", "127.0.0.1", "--directory", webviewDir]
```

```swift
// WebViewBridge.swift — 通过 HTTP 加载
webView.load(URLRequest(url: URL(string: "http://localhost:\(port)/index.html")!))
```

这样 ES module 在 `http://` 协议下可以正常加载，`acquireVsCodeApi` shim 通过 `WKUserScript(atDocumentStart:)` 注入。

## 附带修复的问题

### 1. SwiftUI 重复创建 WebViewBridge

**问题**：SwiftUI 的 `NSViewRepresentable` 会多次调用 `makeNSView`，导致多个 WebViewBridge 实例和多个 HTTP 服务器进程。

**修复**：单例模式 + 在 App `init()` 中预初始化：

```swift
// PixelAgentsApp.swift
init() {
    _ = WebViewBridge.shared
}

// WebViewBridge.swift
private static var _shared: WebViewBridge?
static var shared: WebViewBridge {
    if _shared == nil { _shared = WebViewBridge() }
    return _shared!
}
```

### 2. NWListener 端口获取失败

**问题**：最初尝试用 `Network.framework` 的 `NWListener` 实现 HTTP 服务器，但 `NWListener.port` 在 `.ready` 状态下返回 nil，无法获取实际端口。

**修复**：改用 Python 的 `http.server` 模块，先用 `socket.bind(('', 0))` 获取空闲端口，再启动服务器。

### 3. NSLog vs print

**问题**：macOS GUI 应用中 `print()` 输出不会出现在终端标准输出中，调试信息丢失。

**修复**：调试阶段使用 `NSLog()`，输出会写入系统日志，可通过以下命令查看：

```bash
/usr/bin/log show --predicate 'process == "ClaudePixelAgents" AND eventMessage CONTAINS "[WebViewBridge]"' --last 1m --style compact
```

## 消息通道架构

修复后的完整消息流：

```
React (webview)                        Swift (WKWebView)
     |                                       |
     | acquireVsCodeApi().postMessage()      |
     | → window.webkit.messageHandlers       |
     |   .claudePixelAgents.postMessage()    |
     | ──────────────────────────────────→   |
     |                                       | WKScriptMessageHandler
     |                                       | .userContentController(_:didReceive:)
     |                                       |
     | window.addEventListener('message')    |
     | ← window.postMessage(data)            |
     | ← evaluateJavaScript(...)             |
     | ←──────────────────────────────────   |
```

- **acquireVsCodeApi shim**：通过 `WKUserScript(injectionTime: .atDocumentStart)` 注入，在 ES module 执行前就绑定到 `window` 上
- **React 侧**：`PostMessageTransport` 调用 `acquireVsCodeApi().postMessage()` 发送消息
- **Swift 侧**：`WKScriptMessageHandler` 接收消息并路由到对应处理器

## 涉及修改的文件

| 文件 | 修改内容 |
|------|---------|
| `WebViewBridge.swift` | 改用本地 HTTP 服务器加载；单例模式；WKUserScript 注入 shim |
| `LocalServer.swift` | 完全重写：NWListener → Python http.server |
| `ContentView.swift` | 使用 `WebViewBridge.shared` 单例 |
| `PixelAgentsApp.swift` | 在 `init()` 中预初始化 WebViewBridge |

---

# Agent 会话检测问题排查与修复记录

## 问题现象

应用构建成功，窗口正常弹出，但 AgentTracker 无法检测到任何 Claude 会话，日志只显示 "Executing command" 后没有后续输出。

## 根本原因

**`claude agents --json` 命令在执行时等待标准输入输入，导致进程阻塞。**

当直接在终端运行应用时：
1. `Process` 对象的标准输入（stdin）默认连接到终端
2. `claude agents --json` 命令可能在某些情况下等待输入
3. `readDataToEndOfFile()` 在等待命令输出，但命令在等待输入
4. 导致死锁，最终超时

**关键证据**：
- 使用 `swift run 2>&1 | head -30 &` 运行时正常（stdout 被重定向）
- 直接在终端运行 `swift run` 或 `.build/debug/ClaudePixelAgents` 时失败
- 添加超时后显示 "Command timed out"

## 解决方案

### 1. 添加标准输入管道并关闭

```swift
// AgentTracker.swift — 防止命令等待输入
let stdin = Pipe()
task.standardInput = stdin

do {
    try task.run()
} catch {
    NSLog("[AgentTracker] Failed to run claude agents: \(error)")
    return
}

// 关闭输入管道（告诉命令没有更多输入）
stdin.fileHandleForReading.closeFile()
```

### 2. 添加超时机制

```swift
// 设置超时（5秒）
let timeoutItem = DispatchWorkItem { [weak task] in
    task?.terminate()
    NSLog("[AgentTracker] Command timed out after 5 seconds")
}
DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutItem)

// 读取输出（必须在waitUntilExit之前）
let data = stdout.fileHandleForReading.readDataToEndOfFile()
let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

timeoutItem.cancel()
task.waitUntilExit()
```

### 3. 修复管道读取顺序

```swift
// 之前（错误）
task.waitUntilExit()  // 阻塞等待进程结束
let data = stdout.fileHandleForReading.readDataToEndOfFile()  // 永远不会执行

// 之后（正确）
let data = stdout.fileHandleForReading.readDataToEndOfFile()  // 先读取输出
task.waitUntilExit()  // 再等待进程结束
```

### 4. 添加详细日志

```swift
NSLog("[AgentTracker] Checking NVM path: \(nvmPath)")
NSLog("[AgentTracker] Found Node versions: \(versions)")
NSLog("[AgentTracker] Checking \(claudeBin): exists=\(exists)")
NSLog("[AgentTracker] Executing command: \(command)")
NSLog("[AgentTracker] Process started with PID: \(task.processIdentifier)")
NSLog("[AgentTracker] claude agents output: \(output.prefix(300))")
NSLog("[AgentTracker] claude agents stderr: \(errorOutput.prefix(300))")
NSLog("[AgentTracker] Found \(sessions.count) sessions")
```

## 附加问题：会话类型过滤

### 问题

最初代码只检测 `kind == "background"` 的会话：

```swift
guard let sessionId = sessionDict["sessionId"] as? String,
      let kind = sessionDict["kind"] as? String,
      kind == "background" else { continue }
```

导致无法检测到 `interactive` 类型的会话。

### 解决

移除类型过滤，允许检测所有会话类型：

```swift
guard let sessionId = sessionDict["sessionId"] as? String,
      let kind = sessionDict["kind"] as? String else { continue }
// 暂时禁用 background 过滤，允许检测所有会话类型
// if kind != "background" { continue }
```

## 涉及修改的文件

| 文件 | 修改内容 |
|------|---------|
| `AgentTracker.swift` | 添加 stdin 管道、超时机制、修复管道读取顺序、添加详细日志、移除会话类型过滤 |

## 调试技巧

### 1. 查看系统日志

```bash
# 查看所有 AgentTracker 日志
log show --predicate 'process == "ClaudePixelAgents" AND eventMessage CONTAINS "AgentTracker"' --last 5m

# 查看命令执行日志
log show --predicate 'process == "ClaudePixelAgents" AND eventMessage CONTAINS "Executing command"' --last 5m

# 查看超时日志
log show --predicate 'process == "ClaudePixelAgents" AND eventMessage CONTAINS "timed out"' --last 5m
```

### 2. 手动测试 Claude 命令

```bash
# 测试命令是否正常工作
/Users/xuzhaowen/.nvm/versions/node/v22.15.0/bin/claude agents --json

# 测试命令执行时间
time /Users/xuzhaowen/.nvm/versions/node/v22.15.0/bin/claude agents --json > /dev/null 2>&1
```

### 3. 检查 NVM 路径

```bash
# 检查 NVM 目录
ls -la ~/.nvm/versions/node/

# 检查 claude 可执行文件
ls -la ~/.nvm/versions/node/v22.15.0/bin/claude
```

## 经验总结

1. **Process 标准输入**：当使用 `Process` 执行命令时，如果命令可能等待输入，必须关闭 stdin 或提供输入
2. **管道读取顺序**：必须在 `waitUntilExit()` 之前读取输出，否则会死锁
3. **超时机制**：长时间运行的命令应该添加超时，防止应用无响应
4. **环境差异**：同一命令在不同环境下行为可能不同（如重定向 vs 直接运行）
5. **详细日志**：添加足够的日志可以帮助快速定位问题
