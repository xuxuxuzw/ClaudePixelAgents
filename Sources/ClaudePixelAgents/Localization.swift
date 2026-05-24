import Foundation

enum Language: String {
    case chinese = "zh"
    case english = "en"
}

class Localization {
    static let shared = Localization()

    var currentLanguage: Language {
        get {
            if let raw = UserDefaults.standard.string(forKey: "claudePixelAgents_language"),
               let lang = Language(rawValue: raw) {
                return lang
            }
            return .chinese
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "claudePixelAgents_language")
        }
    }

    private init() {}

    // MARK: - UI Strings

    var working: String {
        switch currentLanguage {
        case .chinese: return "工作中"
        case .english: return "Working"
        }
    }

    var waiting: String {
        switch currentLanguage {
        case .chinese: return "等待中"
        case .english: return "Waiting"
        }
    }

    var permissionNeeded: String {
        switch currentLanguage {
        case .chinese: return "需要许可"
        case .english: return "Permission needed"
        }
    }

    var reading: String {
        switch currentLanguage {
        case .chinese: return "正在读取"
        case .english: return "Reading"
        }
    }

    var writing: String {
        switch currentLanguage {
        case .chinese: return "正在写入"
        case .english: return "Writing"
        }
    }

    var editing: String {
        switch currentLanguage {
        case .chinese: return "正在编辑"
        case .english: return "Editing"
        }
    }

    var hired: String {
        switch currentLanguage {
        case .chinese: return "入职"
        case .english: return "Hired"
        }
    }

    var fired: String {
        switch currentLanguage {
        case .chinese: return "离职"
        case .english: return "Fired"
        }
    }

    func welcomeBanner(name: String) -> String {
        switch currentLanguage {
        case .chinese: return "欢迎 \(name) 加入团队！"
        case .english: return "Welcome \(name) to the team!"
        }
    }

    var windowTitle: String {
        switch currentLanguage {
        case .chinese: return "Claude 像素办公室"
        case .english: return "Claude Pixel Office"
        }
    }
}
