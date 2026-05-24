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
