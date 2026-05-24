# ClaudePixelAgents - 实现计划

## 背景

创建一个原生 macOS 应用，将 Claude Code 代理显示为像素风格的动画角色，场景是一个虚拟办公室。结合 ClaudeGUI 的 CLI 集成模式和 pixel-agents 的 React/Canvas 渲染，通过 WKWebView 嵌入。

**关键决策**：SwiftUI 壳 + WKWebView，纯像素办公室界面（无终端），仅 JSONL 轮询（无 hooks）。

## 架构

```
SwiftUI 应用壳
  +-- WKWebView (pixel-agents 的 webview-ui，零源码修改)
  +-- AgentTracker (JSONL 轮询 + 会话发现)
  +-- AssetLoader (CoreGraphics 解码 PNG 资源)
```

**传输桥接核心技巧**：通过 WKWebView 的 user script 注入 `acquireVsCodeApi()` 垫片。webview 的 `PostMessageTransport` 无需修改——它通过 `window.webkit.messageHandlers` 发送消息，Swift 端用 `WKScriptMessageHandler` 接收；Swift 端通过 `evaluateJavaScript("window.postMessage(...)")` 发送，webview 端用 `window.addEventListener('message')` 接收。

## 项目结构

```
ClaudePixelAgents/
  Package.swift
  Sources/ClaudePixelAgents/
    PixelAgentsApp.swift          # @main SwiftUI 应用入口
    ContentView.swift             # WKWebView 包装器
    WebViewBridge.swift           # WKWebView + 消息桥接 + acquireVsCodeApi 垫片
    AssetLoader.swift             # PNG 解码 + 资源加载序列
    AgentTracker.swift            # 轮询 `claude agents --json`，管理 agent 生命周期
    TranscriptWatcher.swift       # 每个 agent 的 JSONL 文件轮询 (500ms)
    TranscriptParser.swift        # JSONL 记录解析 -> ServerMessage 类型
    Localization.swift            # 中英文切换 (L10n 枚举，zh/en 切换)
    AgentNames.swift              # Agent 随机名字池 (中文名 + 英文名各30+)
    AgentRoles.swift              # Agent 岗位池 (中文岗位 + 英文岗位各20+)
    EmploymentLog.swift           # 入职/离职记录 (时间戳 + 名字 + 岗位)
    DayNightCycle.swift           # 昼夜切换 (根据系统时间，白天明亮/夜晚微暗)
    CoffeeBreak.swift             # 喝咖啡/摸鱼行为逻辑
    AmbientSound.swift            # 环境音效管理 (键盘声/通知音)
```

## 实现阶段

### 阶段 1：Shell + 传输桥接

1. **Package.swift** -- SPM 配置，无外部依赖，macOS 14+，打包 webview-ui 资源
2. **PixelAgentsApp.swift** -- SwiftUI `@main`，`NSApplicationDelegateAdaptor` 管理窗口生命周期
3. **ContentView.swift** -- `NSViewRepresentable` 包装 `WKWebView`，全屏显示像素办公室
4. **WebViewBridge.swift** -- 核心集成点：
   - `WKUserContentController.addUserScript()` 在文档开始时注入 `acquireVsCodeApi` 垫片
   - `WKScriptMessageHandler` 通过 `window.webkit.messageHandlers` 接收 webview 消息
   - `evaluateJavaScript("window.postMessage(...)")` 向 webview 发送消息
   - 收到 `webviewReady` -> 触发资源加载序列
5. 将 `pixel-agents/dist/` 目录打包为应用资源，通过 `loadFileURL` 加载 `index.html`

**验证**：webview 加载成功，显示加载状态（尚无办公室画面——因为资源还没发送）。

### 阶段 2：资源加载

将 `browserMock.ts` 的逻辑移植到 Swift，使用 CoreGraphics 解码 PNG：

1. **PngDecoder.swift** -- `CGImageSource` -> RGBA 像素 -> `#RRGGBBAA` 十六进制字符串
2. **AssetLoader.swift** -- 按顺序加载并解码资源，向 webview 发送消息：
   - `characterSpritesLoaded`（6 个 PNG，每个 112x96 -> 3 方向 x 7 帧 x 16x32）
   - `floorTilesLoaded`（9 个 PNG，每个 16x16）
   - `wallTilesLoaded`（1 个 PNG，64x128 -> 16 个 bitmask 片段）
   - `furnitureAssetsLoaded`（25+ 个 PNG + furniture-catalog.json）
   - `layoutLoaded`（default-layout-1.json）
   - `settingsLoaded`

**验证**：办公室渲染出家具、地板、墙壁、角色坐在桌前。

### 阶段 3：Agent 追踪 + 自动工位分配

将 `transcriptParser.ts` + `fileWatcher.ts` 的核心逻辑移植到 Swift：

1. **AgentTracker.swift** -- 每 5 秒轮询 `claude agents --json`（复用 ClaudeGUI 的模式）
2. **TranscriptWatcher.swift** -- 每个 agent 的 JSONL 轮询间隔 500ms，启动时跳到文件末尾
3. **TranscriptParser.swift** -- 解析 JSONL 记录，生成 ServerMessage 类型：
   - `assistant` + `tool_use` -> `agentToolStart` + `agentStatus(active)`
   - `user` + `tool_result` -> `agentToolDone`
   - `system` + `turn_duration` -> `agentToolsClear` + `agentStatus(waiting)`
4. 启发式定时器：权限等待 (7s)、文字空闲 (5s)、工具完成延迟 (300ms)
5. **AgentNames.swift** -- 创建 agent 时调用 `AgentNames.randomName(for:)` 分配随机名字
6. **AgentRoles.swift** -- 创建 agent 时调用 `AgentRoles.randomRole(for:)` 分配随机岗位

#### 自动工位分配流程

当 `AgentTracker` 发现新 agent 时：

```
发现新 session -> 分配随机名字 + 岗位 -> 记录入职事件 -> 发送 agentCreated 消息到 webview
                                     |
                                     v
                              webview OfficeState.addAgent(id)
                                     |
                                     v
                              自动分配下一个空闲工位（webview 内置逻辑）
                                     |
                                     v
                              发送 saveAgentSeats 回 Swift 端
                                     |
                                     v
                              Swift 持久化到 ~/.pixel-agents/agent-seats.json
```

- **Swift 端**：发现新 session 时发送 `agentCreated` 消息（含 id + name），不指定 seatId
- **webview 端**：`OfficeState.addAgent()` 自动找到下一个空闲座位（遍历 `seats` Map 找未占用的）
- **回写持久化**：webview 分配座位后发送 `saveAgentSeats`，Swift 端保存到本地 JSON 文件
- **离职流程**：session 结束时记录离职事件 → 发送 `agentClosed` 消息 → webview 播放退场特效 → 释放工位
- **恢复已有 agent**：启动时读取 `agent-seats.json`，发送 `existingAgents` 消息时带上已保存的 seatId
- **工位耗尽处理**：当所有座位被占用，新 agent 仍可创建但会站在办公室中央（wander 状态），直到有 agent 退出释放座位

**验证**：在另一个终端运行 `claude --bg`，像素办公室中自动出现一个有名字的角色并坐在空闲工位上开始动画。退出 agent 后，下次新 agent 自动继承该工位。

### 阶段 4：本地化 + Agent 名字

1. **Localization.swift** -- 参考 ClaudeGUI 的 `Localization.swift` 模式：
   - `L10n` 枚举，所有 UI 字符串的中英文 computed property
   - `Localization.shared` 单例，`currentLanguage`（zh/en）切换
   - UserDefaults 持久化语言偏好
   - 关键字符串：
     - 窗口标题、菜单项、设置面板
     - Agent 状态文字："工作中" / "Working"、"等待中" / "Waiting"、"需要许可" / "Permission needed"
     - 工具状态："正在读取" / "Reading"、"正在写入" / "Writing"、"正在编辑" / "Editing" 等
   - 语言切换时通过 JS 桥接通知 webview 更新显示

2. **AgentNames.swift** -- Agent 随机名字池，每个 Agent 创建时随机分配：
   - **中文名（30+）**：小青、墨竹、星河、云起、知秋、若水、清风、明月、松间、石韵、灵犀、拾光、逐梦、归燕、听雨、踏雪、浮云、流萤、破晓、凌霄、微澜、深蓝、赤焰、翠微、白露、暮色、晨曦、远山、幽兰、素心
   - **英文名（30+）**：Ada、Bolt、Cipher、Dash、Echo、Flux、Glimmer、Haze、Iris、Jet、Kite、Luna、Milo、Nova、Onyx、Pixel、Quill、Rune、Spark、Terra、Ursa、Vex、Wren、Xeno、Yara、Zephyr、Archer、Blaze、Coral、Drift
   - 创建 Agent 时：`AgentNames.randomName(for: language)` 根据当前语言选名字
   - 名字通过 `agentCreated` 消息的 `name` 字段发送给 webview 显示

3. **AgentRoles.swift** -- Agent 随机岗位池，每个 Agent 创建时随机分配：
   - **中文岗位（25+）**：前端工程师、后端工程师、全栈工程师、产品经理、UI 设计师、测试工程师、数据工程师、运维工程师、架构师、算法工程师、安全工程师、数据库管理员、技术总监、项目经理、DevOps 工程师、移动端开发、嵌入式开发、游戏开发、AI 训练师、技术作家、代码审查员、性能优化师、系统分析师、解决方案架构师、技术顾问
   - **英文岗位（25+）**：Frontend Engineer、Backend Engineer、Full Stack Engineer、Product Manager、UI Designer、QA Engineer、Data Engineer、DevOps Engineer、Architect、ML Engineer、Security Engineer、DBA、Tech Lead、Project Manager、Mobile Developer、Embedded Developer、Game Developer、AI Trainer、Tech Writer、Code Reviewer、Performance Engineer、Systems Analyst、Solution Architect、Tech Consultant、SRE
   - 创建 Agent 时：`AgentRoles.randomRole(for: language)` 根据当前语言选岗位
   - 岗位通过 `agentCreated` 消息的 `role` 字段发送给 webview，显示在角色名字下方
   - webview 中 ToolOverlay 组件显示格式：`名字\n岗位`（如 "小青\n前端工程师"）

4. **EmploymentLog.swift** -- 入职/离职记录系统：
   - **数据模型**：每条记录包含时间戳、agent 名字、岗位、事件类型（hire/fire）
   - **入职事件**：agent 被发现时记录 `EmploymentRecord(time: now, name: "小青", role: "前端工程师", event: .hire)`
   - **离职事件**：agent 被移除时记录 `EmploymentRecord(time: now, name: "小青", role: "前端工程师", event: .fire)`
   - **持久化**：保存到 `~/.pixel-agents/employment-log.json`，启动时加载历史记录
   - **像素办公室中的展示**：
     - 入职时：角色从办公室门口走入，带 Matrix 入场特效，头顶弹出"入职"气泡
     - 离职时：角色向办公室门口走出，带 Matrix 退场特效，头顶弹出"离职"气泡
   - **日志面板**：可通过菜单打开一个小面板，按时间倒序显示所有入职/离职记录（如"05-24 14:30 小青（前端工程师）入职"、"05-24 15:45 Ada（后端工程师）离职"）
   - **中英文切换**：入职 = "入职" / "Hired"，离职 = "离职" / "Fired"

#### 昼夜切换系统

- **`DayNightCycle.swift`**：根据 macOS 系统时间自动切换白天/黑夜
  - 白天 (6:00-18:00)：正常亮度（brightness = 1.0）
  - 黄昏过渡 (18:00-20:00)：从 1.0 渐变到 0.7
  - 夜晚 (20:00-6:00)：微暗（brightness = 0.7）
  - 黎明过渡 (6:00-8:00)：从 0.7 渐变到 1.0
- **实现方式**：
  - Swift 端每 5 分钟检查一次系统时间，计算当前 brightness 值
  - 通过 `dayNightUpdate` 消息将 brightness 值发送给 webview
  - webview 在 Canvas 渲染后叠加一个半透明黑色遮罩（opacity = 1.0 - brightness）
  - 遮罩跟随办公室缩放和平移，始终覆盖整个可视区域
- **视觉效果**：夜晚时办公室整体微微变暗，营造温馨的深夜加班氛围
- **不影响动画**：昼夜切换仅改变画面明暗度，不影响角色动画和交互逻辑

### 阶段 5：打磨 + 真实办公室氛围

#### 基础打磨
- 通过 `~/.pixel-agents/layout.json` 保存/加载布局
- 通过 `~/.pixel-agents/agent-seats.json` 保存/加载工位分配
- 从应用内启动 agent（菜单按钮）
- 窗口标题显示 agent 数量
- 菜单栏添加语言切换：中文 / English

#### 工位名牌
- 每个工位上方显示 agent 的名字和岗位（如"小青 · 前端工程师"）
- 格式：名字用白色粗体，岗位用灰色小字，中间用 "·" 分隔
- agent 离开工位时名牌变灰，回来时恢复亮色
- 名牌跟随工位位置，不遮挡角色动画

#### 喝咖啡 / 摸鱼行为
- agent 空闲超过 30 秒后，有一定概率（30%）触发"摸鱼"行为
- 角色从工位站起来，走到办公室的茶水间/休息区位置
- 坐下停留 15-30 秒（头顶弹出咖啡杯 emoji 气泡）
- 然后走回工位继续待命
- 这个行为让办公室看起来更生动，不只是角色站着不动

#### 环境音效
- **键盘声**：agent 打字（TYPE 状态）时播放轻微的键盘敲击音效
- **通知音**：agent 完成任务（waiting）时播放完成提示音
- **权限音**：agent 需要权限时播放提醒音
- 可在设置中开关音效（复用 pixel-agents 的 `notificationSound.ts` 逻辑）
- Swift 端通过 `NSSound` 或 webview 内播放

#### 欢迎横幅
- 新 agent 入职时，办公室顶部弹出横幅："欢迎 XXX 加入团队！" / "Welcome XXX to the team!"
- 横幅停留 5 秒后自动消失（带淡出动画）
- 中英文根据当前语言切换

## 关键参考文件

| 用途 | 文件 |
|------|------|
| 传输协议契约 | `pixel-agents/webview-ui/src/transport/postMessageTransport.ts` |
| 资源加载序列 | `pixel-agents/webview-ui/src/browserMock.ts` |
| JSONL 解析逻辑 | `pixel-agents/server/src/transcriptParser.ts` |
| JSONL 文件监听 | `pixel-agents/server/src/fileWatcher.ts` |
| 会话轮询模式 | `ClaudeGUI/Sources/ClaudeGUI/MainWindowController.swift`（L552-636） |
| Webview 消息处理 | `pixel-agents/webview-ui/src/hooks/useExtensionMessages.ts` |
| 本地化参考 | `ClaudeGUI/Sources/ClaudeGUI/Localization.swift` |

## MVP 不包含

- 布局编辑器（仅查看模式）
- 终端视图
- 侧边栏
- Hooks 安装
- 子 agent / 团队检测
- 多窗口支持
