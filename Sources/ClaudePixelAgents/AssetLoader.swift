import Foundation
import CoreGraphics
import ImageIO

class AgentAssetLoader {
    private weak var bridge: WebViewBridge?
    private let resourceBundle: Bundle?

    private let charFrameW = 16
    private let charFrameH = 32
    private let charFramesPerRow = 7
    private let charDirections = ["down", "up", "right"]
    private let floorTileSize = 16
    private let wallGridCols = 4
    private let wallPieceW = 16
    private let wallPieceH = 32
    private let wallBitmaskCount = 16

    init(bridge: WebViewBridge) {
        self.bridge = bridge
        self.resourceBundle = Self.findResourceBundle()
    }

    private static func findResourceBundle() -> Bundle? {
        let bundleName = "ClaudePixelAgents_ClaudePixelAgents"

        // Check all bundles
        for bundle in Bundle.allBundles {
            if bundle.bundlePath.contains(bundleName) {
                print("[AssetLoader] Found bundle: \(bundle.bundlePath)")
                return bundle
            }
        }

        // Try to find bundle next to executable
        let execPath = CommandLine.arguments[0] ?? ""
        let execDir = (execPath as NSString).deletingLastPathComponent
        let possibleBundlePath = execDir + "/\(bundleName).bundle"
        if FileManager.default.fileExists(atPath: possibleBundlePath),
           let bundle = Bundle(path: possibleBundlePath) {
            print("[AssetLoader] Found bundle at: \(possibleBundlePath)")
            return bundle
        }

        // Try parent directory
        let parentDir = (execDir as NSString).deletingLastPathComponent
        let parentBundlePath = parentDir + "/\(bundleName).bundle"
        if FileManager.default.fileExists(atPath: parentBundlePath),
           let bundle = Bundle(path: parentBundlePath) {
            print("[AssetLoader] Found bundle at: \(parentBundlePath)")
            return bundle
        }

        NSLog("[AssetLoader] Bundle not found, using Bundle.main")
        return Bundle.main
    }

    func loadAllAssets() {
        NSLog("[AssetLoader] Starting asset loading...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.doLoadAllAssets()
        }
    }

    private func doLoadAllAssets() {
        loadCharacters()
        loadFloors()
        loadWalls()
        loadFurniture()
        loadLayout()
        sendSettings()
        NSLog("[AssetLoader] All assets loaded")
    }

    // MARK: - Characters

    private func loadCharacters() {
        var characters: [[String: Any]] = []
        for i in 0..<6 {
            guard let bundle = resourceBundle else {
                NSLog("[AssetLoader] Resource bundle is nil")
                return
            }
            guard let url = bundle.url(forResource: "char_\(i)", withExtension: "png", subdirectory: "webview/assets/characters"),
                  let pngData = try? Data(contentsOf: url),
                  let decoded = decodePng(pngData) else {
                NSLog("[AssetLoader] Failed to load char_\(i).png")
                continue
            }
            var byDir: [String: Any] = [:]
            for (dirIdx, dir) in charDirections.enumerated() {
                var frames: [[[String]]] = []
                for frame in 0..<charFramesPerRow {
                    let sprite = sliceRegion(
                        pixels: decoded.pixels,
                        imgW: decoded.width,
                        imgH: decoded.height,
                        ox: frame * charFrameW,
                        oy: dirIdx * charFrameH,
                        w: charFrameW,
                        h: charFrameH
                    )
                    frames.append(sprite)
                }
                byDir[dir] = frames
            }
            characters.append(byDir)
        }
        sendToWebview(["type": "characterSpritesLoaded", "characters": characters])
    }

    // MARK: - Floors

    private func loadFloors() {
        var floors: [[[String]]] = []
        for i in 0..<9 {
            guard let bundle = resourceBundle,
                  let url = bundle.url(forResource: "floor_\(i)", withExtension: "png", subdirectory: "webview/assets/floors"),
                  let pngData = try? Data(contentsOf: url),
                  let decoded = decodePng(pngData) else {
                NSLog("[AssetLoader] Failed to load floor_\(i).png")
                continue
            }
            let sprite = sliceRegion(
                pixels: decoded.pixels,
                imgW: decoded.width,
                imgH: decoded.height,
                ox: 0, oy: 0,
                w: floorTileSize, h: floorTileSize
            )
            floors.append(sprite)
        }
        sendToWebview(["type": "floorTilesLoaded", "sprites": floors])
    }

    // MARK: - Walls

    private func loadWalls() {
        guard let bundle = resourceBundle,
              let url = bundle.url(forResource: "wall_0", withExtension: "png", subdirectory: "webview/assets/walls"),
              let pngData = try? Data(contentsOf: url),
              let decoded = decodePng(pngData) else {
            NSLog("[AssetLoader] Failed to load wall_0.png")
            return
        }
        var set: [[[String]]] = []
        for mask in 0..<wallBitmaskCount {
            let ox = (mask % wallGridCols) * wallPieceW
            let oy = (mask / wallGridCols) * wallPieceH
            let sprite = sliceRegion(
                pixels: decoded.pixels,
                imgW: decoded.width,
                imgH: decoded.height,
                ox: ox, oy: oy,
                w: wallPieceW, h: wallPieceH
            )
            set.append(sprite)
        }
        sendToWebview(["type": "wallTilesLoaded", "sets": [set]])
    }

    // MARK: - Furniture

    private func loadFurniture() {
        var catalog: [[String: Any]] = []
        var sprites: [String: [[String]]] = [:]
        var loadedCount = 0
        var failedCount = 0

        guard let bundle = resourceBundle else {
            NSLog("[AssetLoader] resourceBundle is nil - cannot load furniture")
            return
        }
        guard let catalogURL = bundle.url(forResource: "furniture-catalog", withExtension: "json", subdirectory: "webview/assets") else {
            NSLog("[AssetLoader] furniture-catalog.json not found in bundle: \(bundle.bundlePath)")
            return
        }
        guard let catalogData = try? Data(contentsOf: catalogURL),
              let catalogArray = try? JSONSerialization.jsonObject(with: catalogData) as? [[String: Any]] else {
            NSLog("[AssetLoader] Failed to parse furniture-catalog.json")
            return
        }

        NSLog("[AssetLoader] Loading %d furniture items from catalog", catalogArray.count)

        for entry in catalogArray {
            guard let id = entry["id"] as? String,
                  let file = entry["file"] as? String,
                  let w = entry["width"] as? Int,
                  let h = entry["height"] as? Int else { continue }

            catalog.append(entry as [String: Any])

            let subPath = (file as NSString).deletingLastPathComponent
            let fileName = (file as NSString).lastPathComponent
            let dirPath = subPath.isEmpty ? "furniture" : "furniture/\(subPath)"
            let subDir = "webview/assets/\(dirPath)"

            // Try direct lookup first (file in subDir), then fallback to subdirectory named after the furniture ID
            var url = bundle.url(forResource: fileName, withExtension: nil, subdirectory: subDir)
            if url == nil {
                // Fallback 1: look in subdirectory with the same name as the file (e.g. BIN/BIN.png)
                let fallbackSubDir = "webview/assets/furniture/\(id)"
                url = bundle.url(forResource: fileName, withExtension: nil, subdirectory: fallbackSubDir)
            }
            if url == nil {
                // Fallback 2: for names like CUSHIONED_CHAIR_FRONT, try parent dir CUSHIONED_CHAIR
                let underscoreParts = id.split(separator: "_")
                if underscoreParts.count > 1 {
                    // Try progressively shorter prefixes: CUSHIONED_CHAIR, CUSHIONED
                    for i in stride(from: underscoreParts.count - 1, through: 1, by: -1) {
                        let prefix = underscoreParts.prefix(i).joined(separator: "_")
                        let fallbackDir = "webview/assets/furniture/\(prefix)"
                        if let found = bundle.url(forResource: fileName, withExtension: nil, subdirectory: fallbackDir) {
                            url = found
                            break
                        }
                    }
                }
            }
            if let url = url,
               let pngData = try? Data(contentsOf: url),
               let decoded = decodePng(pngData) {
                let sprite = sliceRegion(
                    pixels: decoded.pixels,
                    imgW: decoded.width,
                    imgH: decoded.height,
                    ox: 0, oy: 0,
                    w: w, h: h
                )
                sprites[id] = sprite
                loadedCount += 1
            } else {
                failedCount += 1
                if failedCount <= 5 {
                    NSLog("[AssetLoader] Failed to load furniture: \(id) file=\(file) subDir=\(subDir)")
                }
            }
        }

        NSLog("[AssetLoader] Furniture loaded: \(loadedCount) ok, \(failedCount) failed")

        // Check message size before sending
        let message: [String: Any] = ["type": "furnitureAssetsLoaded", "catalog": catalog, "sprites": sprites]
        if let jsonData = try? JSONSerialization.data(withJSONObject: message) {
            NSLog("[AssetLoader] Furniture message size: \(jsonData.count) bytes (\(jsonData.count / 1024)KB)")
        }

        sendToWebview(["type": "furnitureAssetsLoaded", "catalog": catalog, "sprites": sprites])
    }

    // MARK: - Layout

    private func loadLayout() {
        let layoutPath = "default-layout-1.json"
        let pixelAgentsDir = NSHomeDirectory() + "/.pixel-agents/layout.json"
        if FileManager.default.fileExists(atPath: pixelAgentsDir),
           let data = FileManager.default.contents(atPath: pixelAgentsDir),
           let layout = try? JSONSerialization.jsonObject(with: data) {
            sendToWebview(["type": "layoutLoaded", "layout": layout])
            return
        }

        guard let bundle = resourceBundle,
              let url = bundle.url(forResource: layoutPath, withExtension: nil, subdirectory: "webview/assets"),
              let data = try? Data(contentsOf: url),
              let layout = try? JSONSerialization.jsonObject(with: data) else {
            sendToWebview(["type": "layoutLoaded", "layout": NSNull()])
            return
        }
        sendToWebview(["type": "layoutLoaded", "layout": layout])
    }

    // MARK: - Settings

    private func sendSettings() {
        sendToWebview([
            "type": "settingsLoaded",
            "soundEnabled": true,
            "extensionVersion": "1.0.0",
            "lastSeenVersion": "1.0",
            "watchAllSessions": true,
            "alwaysShowLabels": false,
            "hooksEnabled": false,
            "hooksInfoShown": true,
        ])
    }

    // MARK: - PNG Decoding

    private func decodePng(_ data: Data) -> (width: Int, height: Int, pixels: [UInt8])? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = context.data else { return nil }
        let pixels = Array(UnsafeBufferPointer(
            start: pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4),
            count: width * height * 4
        ))

        return (width, height, pixels)
    }

    private func sliceRegion(pixels: [UInt8], imgW: Int, imgH: Int, ox: Int, oy: Int, w: Int, h: Int) -> [[String]] {
        var result: [[String]] = []
        for y in 0..<h {
            var row: [String] = []
            for x in 0..<w {
                let px = ox + x
                let py = oy + y
                if px < imgW && py < imgH {
                    let idx = (py * imgW + px) * 4
                    let r = pixels[idx]
                    let g = pixels[idx + 1]
                    let b = pixels[idx + 2]
                    let a = pixels[idx + 3]
                    if a > 2 {
                        row.append(String(format: "#%02X%02X%02X%02X", r, g, b, a))
                    } else {
                        row.append("")  // Empty string = transparent (matches webview sprite cache)
                    }
                } else {
                    row.append("")
                }
            }
            result.append(row)
        }
        return result
    }

    private func sendToWebview(_ message: [String: Any]) {
        // Use sync to guarantee message ordering — furniture must arrive before layout
        DispatchQueue.main.sync { [weak self] in
            self?.bridge?.sendToWebview(message)
        }
    }
}
