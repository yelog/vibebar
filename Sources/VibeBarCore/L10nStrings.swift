// MARK: - Localization Keys

public enum L10nKey: String, CaseIterable, Sendable {
    // Tabs
    case tabGeneral
    case tabAppearance
    case tabAbout

    // Language
    case languageTitle
    case languageDesc
    case langFollowSystem

    // Icon style
    case iconStyleTitle
    case iconStyleDesc
    case iconRing
    case iconParticles
    case iconEnergyBar
    case iconIceGrid

    // Color theme
    case colorThemeTitle
    case colorThemeDesc
    case themeDefault
    case themeCyberpunk
    case themeOcean
    case themePastel
    case themeMonochrome
    case themeCustom

    // System settings
    case systemTitle
    case launchAtLogin
    case launchAtLoginDesc
    case notifyAwaitingInput
    case notifyAwaitingInputDesc
    case notifyAwaitingInputBodyFmt

    // Wrapper command
    case wrapperCommandDisplayName
    case wrapperCommandTitle
    case wrapperCommandDesc
    case wrapperCommandChecking
    case wrapperCommandInstalling
    case wrapperCommandUninstalling
    case wrapperCommandUpdating
    case wrapperCommandInstalled
    case wrapperCommandInstalledExternal
    case wrapperCommandNotInstalled
    case wrapperCommandInstallNow
    case wrapperCommandUninstallNow
    case wrapperCommandPathFmt
    case wrapperCommandExternalHint
    case wrapperCommandRetry

    // About / update section
    case versionFmt
    case updateTitle
    case autoCheckUpdates
    case autoCheckUpdatesDesc
    case checkUpdatesBtn
    case alreadyLatest
    case statsTitle
    case connectTitle
    case runningAgents
    case activeSessions


    // Activity states
    case stateIdle
    case stateRunning
    case stateAwaitingInput
    case stateUnknown
    case stateStopped

    // Sessions / Menu
    case sessionTitle
    case noSessions
    case openSessionsDir
    case purgeStale
    case quit
    case quitVibeBar
    case closeWindow
    case refresh
    case settings
    case totalSessionsFmt
    case updatedFmt
    case menuSubtitleFmt
    case tooltipFmt
    case accessibilityFmt
    case legendText
    case dirUnknown

    // Plugin
    case pluginTitle
    case pluginSuffix
    case pluginClaudeDesc
    case pluginOpenCodeDesc
    case pluginCliNotFoundFmt
    case pluginInstalling
    case pluginUninstalling
    case pluginChecking
    case pluginUpdating
    case pluginNotInstalled
    case pluginInstalled
    case pluginInstall
    case pluginUninstall
    case pluginUpdate
    case pluginFailedFmt
    case pluginRetry
    case pluginRetryUninstall
    case pluginLatestNoUpdatedTime
    case pluginLatestWithUpdatedFmt
    case pluginUpdateNow
    case pluginSkipVersion
    case pluginUpdatePromptTitleFmt
    case pluginUpdatePromptInfoFmt

    // Update checker
    case updateCheckFailed
    case updateConnectErrorFmt
    case updateParseError
    case updateRateLimited
    case updateRateLimitedWithResetFmt
    case updateHTTPStatusFmt
    case updateAlreadyLatest
    case updateAlreadyLatestFmt
    case updateNewVersionFmt
    case updateCurrentInfoFmt
    case updateGoDownload
    case updateRemindLater
    case ok

    // Console messages
    case consoleNotGuiSession
    case consoleRunInTerminal
    case consoleCannotReadSession
    case consoleStatusBarUnavail
}

// MARK: - Translation Table

public enum L10nStrings {
    /// Look up a translation for the given key and language.
    public static func string(_ key: L10nKey, lang: AppLanguage) -> String {
        let effective = lang == .system ? AppLanguage.resolveSystemLanguage() : lang
        return table[key]?[effective] ?? table[key]?[.en] ?? key.rawValue
    }

    // swiftlint:disable function_body_length
    static let table: [L10nKey: [AppLanguage: String]] = [
        // MARK: Tabs
        .tabGeneral: [
            .zh: "通用", .en: "General", .ja: "一般", .ko: "일반",
        ],
        .tabAppearance: [
            .zh: "外观", .en: "Appearance", .ja: "外観", .ko: "외형",
        ],
        .tabAbout: [
            .zh: "关于", .en: "About", .ja: "情報", .ko: "정보",
        ],

        // MARK: Language
        .languageTitle: [
            .zh: "语言", .en: "Language", .ja: "言語", .ko: "언어",
        ],
        .languageDesc: [
            .zh: "选择界面显示语言",
            .en: "Select the display language",
            .ja: "表示言語を選択",
            .ko: "표시 언어 선택",
        ],
        .langFollowSystem: [
            .zh: "跟随系统", .en: "Follow System", .ja: "システムに従う", .ko: "시스템 설정",
        ],

        // MARK: Icon Style
        .iconStyleTitle: [
            .zh: "图标样式", .en: "Icon Style", .ja: "アイコンスタイル", .ko: "아이콘 스타일",
        ],
        .iconStyleDesc: [
            .zh: "选择菜单栏中显示的图标样式",
            .en: "Choose the icon style displayed in the menu bar",
            .ja: "メニューバーに表示するアイコンスタイルを選択",
            .ko: "메뉴 막대에 표시할 아이콘 스타일 선택",
        ],
        .iconRing: [
            .zh: "环形", .en: "Ring", .ja: "リング", .ko: "링",
        ],
        .iconParticles: [
            .zh: "粒子轨道", .en: "Particles", .ja: "パーティクル", .ko: "파티클",
        ],
        .iconEnergyBar: [
            .zh: "能量条", .en: "Energy Bar", .ja: "エナジーバー", .ko: "에너지 바",
        ],
        .iconIceGrid: [
            .zh: "冰格", .en: "Ice Grid", .ja: "アイスグリッド", .ko: "아이스 그리드",
        ],

        // MARK: Color Theme
        .colorThemeTitle: [
            .zh: "颜色方案", .en: "Color Theme", .ja: "カラーテーマ", .ko: "색상 테마",
        ],
        .colorThemeDesc: [
            .zh: "选择会话状态的配色方案",
            .en: "Choose the color theme for session status",
            .ja: "セッション状態の配色を選択",
            .ko: "세션 상태의 색상 테마 선택",
        ],
        .themeDefault: [
            .zh: "默认", .en: "Default", .ja: "デフォルト", .ko: "기본",
        ],
        .themeCyberpunk: [
            .zh: "赛博朋克", .en: "Cyberpunk", .ja: "サイバーパンク", .ko: "사이버펑크",
        ],
        .themeOcean: [
            .zh: "海洋", .en: "Ocean", .ja: "オーシャン", .ko: "오션",
        ],
        .themePastel: [
            .zh: "柔和", .en: "Pastel", .ja: "パステル", .ko: "파스텔",
        ],
        .themeMonochrome: [
            .zh: "单色", .en: "Monochrome", .ja: "モノクロ", .ko: "모노크롬",
        ],
        .themeCustom: [
            .zh: "自定义", .en: "Custom", .ja: "カスタム", .ko: "사용자 지정",
        ],

        // MARK: System Settings
        .systemTitle: [
            .zh: "系统", .en: "System", .ja: "システム", .ko: "시스템",
        ],
        .launchAtLogin: [
            .zh: "开机时自动启动",
            .en: "Launch at Login",
            .ja: "ログイン時に起動",
            .ko: "로그인 시 실행",
        ],
        .launchAtLoginDesc: [
            .zh: "登录 macOS 时自动在后台启动 VibeBar",
            .en: "Automatically launch VibeBar in the background when logging into macOS",
            .ja: "macOS ログイン時に VibeBar をバックグラウンドで自動起動",
            .ko: "macOS 로그인 시 VibeBar를 백그라운드에서 자동 실행",
        ],
        .notifyAwaitingInput: [
            .zh: "等待用户时发送通知",
            .en: "Notify on Awaiting Input",
            .ja: "入力待ちで通知",
            .ko: "입력 대기 시 알림",
        ],
        .notifyAwaitingInputDesc: [
            .zh: "当任意会话进入“等待用户操作”状态时发送系统通知，点击通知可直接展开菜单栏",
            .en: "Send a system notification when any session enters awaiting-input; click to open the menu bar dropdown",
            .ja: "いずれかのセッションが入力待ちになったら通知し、クリックでメニューバーを開きます",
            .ko: "세션이 입력 대기 상태가 되면 시스템 알림을 보내고, 클릭하면 메뉴 막대를 엽니다",
        ],
        .notifyAwaitingInputBodyFmt: [
            .zh: "%@ 等待用户操作",
            .en: "%@ is awaiting your input",
            .ja: "%@ がユーザー操作待ちです",
            .ko: "%@에서 사용자 입력을 기다리는 중입니다",
        ],

        // MARK: Wrapper Command
        .wrapperCommandDisplayName: [
            .zh: "vibebar 命令行",
            .en: "vibebar Command",
            .ja: "vibebar コマンド",
            .ko: "vibebar 명령어",
        ],
        .wrapperCommandTitle: [
            .zh: "命令行", .en: "Command Line", .ja: "コマンドライン", .ko: "명령줄",
        ],
        .wrapperCommandDesc: [
            .zh: "终端 wrapper：`vibebar <claude|codex|opencode|copilot>`。建议主要用于 Codex/GitHub Copilot（暂无插件系统）；Claude/OpenCode 更推荐使用插件方式。",
            .en: "Terminal wrapper: `vibebar <claude|codex|opencode|copilot>`. Recommended mainly for Codex/GitHub Copilot (no plugin system yet); prefer plugins for Claude/OpenCode.",
            .ja: "ターミナル wrapper: `vibebar <claude|codex|opencode|copilot>`。主に Codex/GitHub Copilot 向け（現状プラグインなし）で推奨し、Claude/OpenCode はプラグイン利用を推奨します。",
            .ko: "터미널 wrapper: `vibebar <claude|codex|opencode|copilot>`. 플러그인 시스템이 없는 Codex/GitHub Copilot에 주로 권장하며, Claude/OpenCode는 플러그인 사용을 권장합니다.",
        ],
        .wrapperCommandChecking: [
            .zh: "检测中...",
            .en: "Checking...",
            .ja: "確認中...",
            .ko: "확인 중...",
        ],
        .wrapperCommandInstalling: [
            .zh: "正在安装...",
            .en: "Installing...",
            .ja: "インストール中...",
            .ko: "설치 중...",
        ],
        .wrapperCommandUninstalling: [
            .zh: "正在卸载...",
            .en: "Uninstalling...",
            .ja: "アンインストール中...",
            .ko: "제거 중...",
        ],
        .wrapperCommandUpdating: [
            .zh: "正在更新...",
            .en: "Updating...",
            .ja: "アップデート中...",
            .ko: "업데이트 중...",
        ],
        .wrapperCommandInstalled: [
            .zh: "已安装",
            .en: "Installed",
            .ja: "インストール済み",
            .ko: "설치됨",
        ],
        .wrapperCommandInstalledExternal: [
            .zh: "已安装（外部）",
            .en: "Installed (External)",
            .ja: "インストール済み（外部）",
            .ko: "설치됨(외부)",
        ],
        .wrapperCommandNotInstalled: [
            .zh: "未安装",
            .en: "Not installed",
            .ja: "未インストール",
            .ko: "미설치",
        ],
        .wrapperCommandInstallNow: [
            .zh: "立即安装",
            .en: "Install Now",
            .ja: "今すぐインストール",
            .ko: "지금 설치",
        ],
        .wrapperCommandUninstallNow: [
            .zh: "立即卸载",
            .en: "Uninstall Now",
            .ja: "今すぐアンインストール",
            .ko: "지금 제거",
        ],
        .wrapperCommandPathFmt: [
            .zh: "命令路径: %@",
            .en: "Command path: %@",
            .ja: "コマンドパス: %@",
            .ko: "명령 경로: %@",
        ],
        .wrapperCommandExternalHint: [
            .zh: "检测到外部安装来源，VibeBar 不会自动卸载该命令。",
            .en: "Detected an external installation source. VibeBar will not uninstall it automatically.",
            .ja: "外部インストールを検出したため、VibeBar は自動アンインストールしません。",
            .ko: "외부 설치를 감지했습니다. VibeBar는 이를 자동 제거하지 않습니다.",
        ],
        .wrapperCommandRetry: [
            .zh: "重试",
            .en: "Retry",
            .ja: "再試行",
            .ko: "재시도",
        ],

        // MARK: About / Updates
        .versionFmt: [
            .zh: "版本 %@", .en: "Version %@", .ja: "バージョン %@", .ko: "버전 %@",
        ],
        .updateTitle: [
            .zh: "更新", .en: "Updates", .ja: "アップデート", .ko: "업데이트",
        ],
        .autoCheckUpdates: [
            .zh: "自动检查更新",
            .en: "Automatically Check for Updates",
            .ja: "自動的にアップデートを確認",
            .ko: "자동으로 업데이트 확인",
        ],
        .autoCheckUpdatesDesc: [
            .zh: "启动时检查 GitHub Releases 是否有新版本",
            .en: "Check GitHub Releases for new versions at startup",
            .ja: "起動時に GitHub Releases で新バージョンを確認",
            .ko: "시작 시 GitHub Releases에서 새 버전 확인",
        ],
.checkUpdatesBtn: [
.zh: "检查更新…", .en: "Check for Updates…", .ja: "アップデートを確認…", .ko: "업데이트 확인…",
        ],
        .alreadyLatest: [
            .zh: "已是最新", .en: "is up to date", .ja: "最新です", .ko: "최신 버전입니다",
        ],
        .statsTitle: [
            .zh: "实时状态", .en: "Live Stats", .ja: "リアルタイム統計", .ko: "실시간 통계",
        ],
        .connectTitle: [
            .zh: "联系我们", .en: "Connect", .ja: "連絡先", .ko: "연락처",
        ],
        .runningAgents: [
            .zh: "运行中的代理", .en: "Running Agents", .ja: "実行中エージェント", .ko: "실행 중인 에이전트",
        ],
        .activeSessions: [
            .zh: "活跃会话", .en: "Active Sessions", .ja: "アクティブセッション", .ko: "활성 세션",
        ],

// MARK: Activity States
        .stateIdle: [
            .zh: "空闲", .en: "Idle", .ja: "アイドル", .ko: "유휴",
        ],
        .stateRunning: [
            .zh: "运行中", .en: "Running", .ja: "実行中", .ko: "실행 중",
        ],
        .stateAwaitingInput: [
            .zh: "等待用户", .en: "Awaiting Input", .ja: "入力待ち", .ko: "입력 대기",
        ],
        .stateUnknown: [
            .zh: "未知", .en: "Unknown", .ja: "不明", .ko: "알 수 없음",
        ],
        .stateStopped: [
            .zh: "未启动", .en: "Stopped", .ja: "停止", .ko: "정지",
        ],

        // MARK: Sessions / Menu
        .sessionTitle: [
            .zh: "会话", .en: "Sessions", .ja: "セッション", .ko: "세션",
        ],
        .noSessions: [
            .zh: "当前未检测到支持的 TUI 会话",
            .en: "No supported TUI sessions detected",
            .ja: "サポートされている TUI セッションが検出されません",
            .ko: "지원되는 TUI 세션이 감지되지 않음",
        ],
        .openSessionsDir: [
            .zh: "打开状态目录",
            .en: "Open Status Directory",
            .ja: "ステータスディレクトリを開く",
            .ko: "상태 디렉토리 열기",
        ],
        .purgeStale: [
            .zh: "清理陈旧项",
            .en: "Purge Stale",
            .ja: "古い項目を削除",
            .ko: "오래된 항목 정리",
        ],
        .quit: [
            .zh: "退出", .en: "Quit", .ja: "終了", .ko: "종료",
        ],
        .quitVibeBar: [
            .zh: "退出 VibeBar", .en: "Quit VibeBar", .ja: "VibeBar を終了", .ko: "VibeBar 종료",
        ],
        .closeWindow: [
            .zh: "关闭窗口",
            .en: "Close Window",
            .ja: "ウインドウを閉じる",
            .ko: "윈도우 닫기",
        ],
        .refresh: [
            .zh: "刷新", .en: "Refresh", .ja: "更新", .ko: "새로고침",
        ],
        .settings: [
            .zh: "设置...", .en: "Settings...", .ja: "設定...", .ko: "설정...",
        ],
        .totalSessionsFmt: [
            .zh: "总会话: %d",
            .en: "Sessions: %d",
            .ja: "セッション合計: %d",
            .ko: "총 세션: %d",
        ],
        .updatedFmt: [
            .zh: "更新: %@",
            .en: "Updated: %@",
            .ja: "更新: %@",
            .ko: "업데이트: %@",
        ],
        .menuSubtitleFmt: [
            .zh: "总会话: %d · 更新: %@",
            .en: "Sessions: %d · Updated: %@",
            .ja: "セッション合計: %d · 更新: %@",
            .ko: "총 세션: %d · 업데이트: %@",
        ],
        .tooltipFmt: [
            .zh: "VibeBar 会话总数: %d",
            .en: "VibeBar sessions: %d",
            .ja: "VibeBar セッション数: %d",
            .ko: "VibeBar 세션 수: %d",
        ],
        .accessibilityFmt: [
            .zh: "VibeBar 会话总数 %d",
            .en: "VibeBar total sessions %d",
            .ja: "VibeBar セッション合計 %d",
            .ko: "VibeBar 총 세션 %d",
        ],
        .legendText: [
            .zh: "颜色: 亮绿=运行中, 亮黄=等待用户, 亮蓝=空闲",
            .en: "Colors: green=running, yellow=awaiting, blue=idle",
            .ja: "色: 緑=実行中, 黄=入力待ち, 青=アイドル",
            .ko: "색상: 초록=실행 중, 노랑=입력 대기, 파랑=유휴",
        ],
        .dirUnknown: [
            .zh: "目录未知",
            .en: "Unknown directory",
            .ja: "ディレクトリ不明",
            .ko: "디렉토리 알 수 없음",
        ],

        // MARK: Plugin
        .pluginTitle: [
            .zh: "插件", .en: "Plugins", .ja: "プラグイン", .ko: "플러그인",
        ],
        .pluginSuffix: [
            .zh: " 插件", .en: " Plugin", .ja: " プラグイン", .ko: " 플러그인",
        ],
        .pluginClaudeDesc: [
            .zh: "推荐接入方式：通过插件把 Claude Code 会话状态回传给 VibeBar（优先于 `vibebar claude` wrapper），并支持安装、卸载和更新。",
            .en: "Recommended integration for Claude Code: use the plugin (preferred over `vibebar claude`) to report session status to VibeBar, with install/uninstall/update support.",
            .ja: "Claude Code の推奨連携方式です。`vibebar claude` wrapper よりプラグイン利用を優先し、セッション状態の送信とインストール/削除/更新を行います。",
            .ko: "Claude Code의 권장 연동 방식입니다. `vibebar claude` wrapper보다 플러그인 사용을 우선하며, 세션 상태 전달과 설치/제거/업데이트를 지원합니다.",
        ],
        .pluginOpenCodeDesc: [
            .zh: "推荐接入方式：通过插件把 OpenCode 会话状态回传给 VibeBar（优先于 `vibebar opencode` wrapper），并支持安装、卸载和更新。",
            .en: "Recommended integration for OpenCode: use the plugin (preferred over `vibebar opencode`) to report session status to VibeBar, with install/uninstall/update support.",
            .ja: "OpenCode の推奨連携方式です。`vibebar opencode` wrapper よりプラグイン利用を優先し、セッション状態の送信とインストール/削除/更新を行います。",
            .ko: "OpenCode의 권장 연동 방식입니다. `vibebar opencode` wrapper보다 플러그인 사용을 우선하며, 세션 상태 전달과 설치/제거/업데이트를 지원합니다.",
        ],
        .pluginCliNotFoundFmt: [
            .zh: "未检测到 %@ 命令行",
            .en: "%@ CLI not found",
            .ja: "%@ CLI が見つかりません",
            .ko: "%@ CLI를 찾을 수 없음",
        ],
        .pluginInstalling: [
            .zh: "正在安装...",
            .en: "Installing...",
            .ja: "インストール中...",
            .ko: "설치 중...",
        ],
        .pluginUninstalling: [
            .zh: "正在卸载...",
            .en: "Uninstalling...",
            .ja: "アンインストール中...",
            .ko: "제거 중...",
        ],
        .pluginChecking: [
            .zh: "检测中...",
            .en: "Checking...",
            .ja: "確認中...",
            .ko: "확인 중...",
        ],
        .pluginUpdating: [
            .zh: "正在更新...",
            .en: "Updating...",
            .ja: "アップデート中...",
            .ko: "업데이트 중...",
        ],
        .pluginNotInstalled: [
            .zh: "未安装",
            .en: "Not installed",
            .ja: "未インストール",
            .ko: "미설치",
        ],
        .pluginInstalled: [
            .zh: "已安装",
            .en: "Installed",
            .ja: "インストール済み",
            .ko: "설치됨",
        ],
        .pluginInstall: [
            .zh: "安装", .en: "Install", .ja: "インストール", .ko: "설치",
        ],
        .pluginUninstall: [
            .zh: "卸载", .en: "Uninstall", .ja: "アンインストール", .ko: "제거",
        ],
        .pluginUpdate: [
            .zh: "更新", .en: "Update", .ja: "アップデート", .ko: "업데이트",
        ],
        .pluginFailedFmt: [
            .zh: "%@失败",
            .en: "%@ Failed",
            .ja: "%@失敗",
            .ko: "%@ 실패",
        ],
        .pluginRetry: [
            .zh: "重试", .en: "Retry", .ja: "再試行", .ko: "재시도",
        ],
        .pluginRetryUninstall: [
            .zh: "重试卸载",
            .en: "Retry Uninstall",
            .ja: "アンインストール再試行",
            .ko: "제거 재시도",
        ],
        .pluginLatestNoUpdatedTime: [
            .zh: "已是最新版本",
            .en: "Already up to date",
            .ja: "最新バージョンです",
            .ko: "최신 버전입니다",
        ],
        .pluginLatestWithUpdatedFmt: [
            .zh: "已是最新版本，上次更新 %@",
            .en: "Already up to date, last updated %@",
            .ja: "最新バージョンです。前回更新 %@",
            .ko: "최신 버전입니다. 마지막 업데이트 %@",
        ],
        .pluginUpdateNow: [
            .zh: "立即更新",
            .en: "Update Now",
            .ja: "今すぐ更新",
            .ko: "지금 업데이트",
        ],
        .pluginSkipVersion: [
            .zh: "跳过此版本",
            .en: "Skip This Version",
            .ja: "このバージョンをスキップ",
            .ko: "이 버전 건너뛰기",
        ],
        .pluginUpdatePromptTitleFmt: [
            .zh: "%@ 插件有可用更新（%@）",
            .en: "%@ plugin update available (%@)",
            .ja: "%@ プラグインの更新が利用可能（%@）",
            .ko: "%@ 플러그인 업데이트 사용 가능 (%@)",
        ],
        .pluginUpdatePromptInfoFmt: [
            .zh: "当前版本：%@\n可用版本：%@",
            .en: "Current version: %@\nAvailable version: %@",
            .ja: "現在のバージョン: %@\n利用可能なバージョン: %@",
            .ko: "현재 버전: %@\n사용 가능한 버전: %@",
        ],

        // MARK: Update Checker
        .updateCheckFailed: [
            .zh: "检查更新失败",
            .en: "Update Check Failed",
            .ja: "アップデート確認に失敗",
            .ko: "업데이트 확인 실패",
        ],
        .updateConnectErrorFmt: [
            .zh: "无法连接到 GitHub：%@",
            .en: "Cannot connect to GitHub: %@",
            .ja: "GitHub に接続できません: %@",
            .ko: "GitHub에 연결할 수 없습니다: %@",
        ],
        .updateParseError: [
            .zh: "无法解析服务器响应。",
            .en: "Cannot parse server response.",
            .ja: "サーバー応答を解析できません。",
            .ko: "서버 응답을 분석할 수 없습니다.",
        ],
        .updateRateLimited: [
            .zh: "GitHub API 请求过于频繁，请稍后重试。",
            .en: "GitHub API rate limit reached. Please try again later.",
            .ja: "GitHub API のレート制限に達しました。しばらくしてから再試行してください。",
            .ko: "GitHub API 요청 한도에 도달했습니다. 잠시 후 다시 시도하세요.",
        ],
        .updateRateLimitedWithResetFmt: [
            .zh: "GitHub API 请求过于频繁，请在 %@ 后重试。",
            .en: "GitHub API rate limit reached. Please retry after %@.",
            .ja: "GitHub API のレート制限に達しました。%@ 以降に再試行してください。",
            .ko: "GitHub API 요청 한도에 도달했습니다. %@ 이후에 다시 시도하세요.",
        ],
        .updateHTTPStatusFmt: [
            .zh: "GitHub 返回错误（HTTP %d）。",
            .en: "GitHub returned an error (HTTP %d).",
            .ja: "GitHub からエラーが返されました（HTTP %d）。",
            .ko: "GitHub에서 오류를 반환했습니다(HTTP %d).",
        ],
        .updateAlreadyLatest: [
            .zh: "已是最新版本",
            .en: "Already Up to Date",
            .ja: "最新バージョンです",
            .ko: "최신 버전입니다",
        ],
        .updateAlreadyLatestFmt: [
            .zh: "当前版本 %@ 已是最新。",
            .en: "Version %@ is already the latest.",
            .ja: "現在のバージョン %@ は最新です。",
            .ko: "현재 버전 %@(은)는 최신입니다.",
        ],
        .updateNewVersionFmt: [
            .zh: "发现新版本 v%@",
            .en: "New Version v%@ Available",
            .ja: "新バージョン v%@ が利用可能",
            .ko: "새 버전 v%@ 사용 가능",
        ],
        .updateCurrentInfoFmt: [
            .zh: "当前版本: %@\n\n%@",
            .en: "Current version: %@\n\n%@",
            .ja: "現在のバージョン: %@\n\n%@",
            .ko: "현재 버전: %@\n\n%@",
        ],
        .updateGoDownload: [
            .zh: "前往下载", .en: "Download", .ja: "ダウンロード", .ko: "다운로드",
        ],
        .updateRemindLater: [
            .zh: "稍后提醒",
            .en: "Remind Me Later",
            .ja: "後で通知",
            .ko: "나중에 알림",
        ],
        .ok: [
            .zh: "好", .en: "OK", .ja: "OK", .ko: "확인",
        ],

        // MARK: Console Messages
        .consoleNotGuiSession: [
            .zh: "VibeBar error: 当前不是 macOS 图形控制台会话，无法显示右上角菜单栏图标。\n",
            .en: "VibeBar error: Not a macOS graphical console session. Cannot display menu bar icon.\n",
            .ja: "VibeBar error: macOS のグラフィカルコンソールセッションではないため、メニューバーアイコンを表示できません。\n",
            .ko: "VibeBar error: macOS 그래픽 콘솔 세션이 아니므로 메뉴 막대 아이콘을 표시할 수 없습니다.\n",
        ],
        .consoleRunInTerminal: [
            .zh: "请在本机 Terminal.app / iTerm 中直接运行，或打包为 .app 后从 Finder 启动。\n",
            .en: "Please run directly in Terminal.app / iTerm, or launch as a .app bundle from Finder.\n",
            .ja: "Terminal.app / iTerm で直接実行するか、.app バンドルとして Finder から起動してください。\n",
            .ko: "Terminal.app / iTerm에서 직접 실행하거나 .app 번들로 Finder에서 실행하세요.\n",
        ],
        .consoleCannotReadSession: [
            .zh: "VibeBar warning: 无法读取会话信息，继续尝试启动。\n",
            .en: "VibeBar warning: Cannot read session info, continuing startup.\n",
            .ja: "VibeBar warning: セッション情報を読み取れません。起動を続行します。\n",
            .ko: "VibeBar warning: 세션 정보를 읽을 수 없습니다. 시작을 계속합니다.\n",
        ],
        .consoleStatusBarUnavail: [
            .zh: "VibeBar warning: status bar button unavailable. 可能当前会话不是 GUI/Aqua 会话。\n",
            .en: "VibeBar warning: Status bar button unavailable. The current session may not be a GUI/Aqua session.\n",
            .ja: "VibeBar warning: ステータスバーボタンが利用できません。現在のセッションが GUI/Aqua セッションではない可能性があります。\n",
            .ko: "VibeBar warning: 상태 막대 버튼을 사용할 수 없습니다. 현재 세션이 GUI/Aqua 세션이 아닐 수 있습니다.\n",
        ],
    ]
    // swiftlint:enable function_body_length
}
