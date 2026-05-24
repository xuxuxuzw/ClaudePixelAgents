import Foundation

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

    static func randomRole(for language: Language) -> String {
        switch language {
        case .chinese:
            return chineseRoles.randomElement() ?? "工程师"
        case .english:
            return englishRoles.randomElement() ?? "Engineer"
        }
    }
}
