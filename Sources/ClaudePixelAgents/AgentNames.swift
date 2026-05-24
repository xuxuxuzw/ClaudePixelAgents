import Foundation

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

    static func randomName(for language: Language) -> String {
        switch language {
        case .chinese:
            return chineseNames.randomElement() ?? "小助手"
        case .english:
            return englishNames.randomElement() ?? "Agent"
        }
    }
}
