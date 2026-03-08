# Changelog

All notable changes to VibeBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.3] - 2026-03-08

### Fixed
- Align local build number calculation with CI workflow

## [1.3.2] - 2026-03-08

### Added
- Add GitHub download fallback for failed updates

### Fixed
- Terminate vibebar-agent before Sparkle update
- Correct Sparkle version comparison for beta vs stable

## [1.3.1] - 2026-03-08

### Added
- Add session grouping by tool type with toggle setting
- Show live session runtime in dropdown menu
- Add tool icons for CLI agents in menu and settings
- Add dedicated Wrapper section in CLI settings
- Add OpenCode plugin detection method with highest priority
- 调整设置界面尺寸并修复 tab 换行问题

### Fixed
- Right-align install action in plugin section
- Fix correct bundle lookup for released app
- Fix SPM resource bundle copy into app package
- Support Gemini CLI installed via fnm/nvm/brew/macports
- Exclude CLAUDE.md files from SPM targets
- Respect user configuration for detection methods
- Implement active scanning for Gemini transcript files

### Changed
- Trim detector and menu refresh work
- Reduce refresh polling overhead
- Pause auto-refresh while menu is open to prevent flickering
- Optimize performance with dynamic timer, cached icons, and parallel detection
- Improve menu item localization consistency
- Redesign CLI settings detail panel layout
- Replace Claude Code log detection with plugin method
- Remove GitHub Copilot plugin and hook detection
- Optimize dropdown menu layout and visual hierarchy
- Update GitHub Copilot icon to official avatar

## [1.3.1-beta.3] - 2026-03-05

### Added
- add session grouping by tool type with toggle setting
- show live session runtime in dropdown

### Fixed
- right-align install action in plugin section

### Performance
- pause auto-refresh while menu is open to prevent flickering
- optimize VibeBar performance with dynamic timer, cached icons, and parallel detection

### Refactored
- improve menu item localization consistency

### Style
- display plugin version in gray in dropdown menu

### Documentation
- add session runtime implementation plan

## [1.3.1-beta.2] - 2026-03-03

### Added
- add dedicated Wrapper section in CLI settings
- add plugin detection method with highest priority for OpenCode
- show per-session runtime in dropdown menu session list

### Fixed
- implement active scanning for Gemini transcript files
- exclude CLAUDE.md files from SPM targets
- respect user configuration for detection methods
- use process elapsed time (`ps etime`) to derive stable `startedAt` for process-scan sessions

### Changed
- redesign CLI settings detail panel layout
- remove per-tool wrapper section from CLI settings
- replace Claude Code log detection with plugin method
- remove GitHub Copilot plugin and hook detection (unreliable implementation)

## [1.3.1-beta.1] - 2026-03-02

### Fixed
- add correct bundle lookup for released app (fixes crash when opening CLI settings)
- copy SPM resource bundle into app package

## [1.3.1-beta.0] - 2026-03-01

### Added
- add tool icons for CLI agents in menu and settings

### Fixed
- support Gemini CLI installed via fnm/nvm/brew/macports

### Changed
- optimize dropdown menu layout and visual hierarchy
- update GitHub Copilot icon to official avatar

## [1.3.0] - 2026-03-01

### Added
- Integrate Sparkle for automatic in-app updates
- Add beta update channel support
- Add CLI settings tab with per-tool detection configuration
- Add configurable state transition notifications
- Add confirmation dialog for reset to defaults
- Add GitHub Copilot CLI support (process scan, hooks, JSON-RPC server detection)
- Add Gemini CLI support (wrapper, hook events, stream-json parsing)
- Add Aider support (wrapper and notify-based state integration)
- Redesign tool list with install detection
- Improve notification settings UX

### Fixed
- Fix Sparkle channel filtering blocking beta updates
- Fix false notifications on agent/app startup
- Fix menu bar hover and tooltip positioning issues
- Fix CI workflow git conflicts handling
- Fix CDATA markers appearing in changelog UI
- Remove hardcoded SUFeedURL from Info.plist

### Changed
- Update Sparkle feed URL to use custom domain vibebar.yelog.org
- Reduce visual weight of update section
- Update application and documentation logo
- Show beta warning only when beta channel selected
- Immediately clear/detect sessions when toggling CLI tools
- Prewarm WindowServer to eliminate menu bar click delay

## [1.3.0-beta.13] - 2026-03-01

### Fixed
- Use CHANGELOG.md content for GitHub Release notes
- Use --theirs instead of --ours when resolving appcast merge conflicts

## [1.3.0-beta.12] - 2026-03-01

### Changed
- Test automated release workflow with changelog automation

## [1.3.0-beta.11] - 2026-03-01

### Fixed
- Fixed false notifications firing on app startup for idle sessions
- Fixed false notifications when new agent initializes

## [1.3.0-beta.10] - 2026-02-28

### Changed
- Test automated release pipeline

## [1.3.0-beta.9] - 2026-02-28

### Fixed
- Fixed notification firing incorrectly on app startup

## [1.3.0-beta.8] - 2026-02-28

### Fixed
- Fixed CDATA markers appearing in changelog UI

## [1.3.0-beta.7] - 2026-02-28

### Fixed
- Fixed Sparkle channel filtering blocking beta updates

## [1.3.0-beta.6] - 2026-02-28

### Fixed
- Fixed CI workflow git stash bug causing appcast update failures

## [1.3.0-beta.5] - 2026-02-27

### Changed
- Redesigned update section with reduced visual weight
- Conditional beta warning display
- Locked window height with scrolling support
- Redesigned CLI tool list with install detection

### Added
- Confirmation dialog for reset to defaults

### Fixed
- Immediate session cleanup when toggling CLI tools

## [1.3.0-beta.2] - 2026-02-26

### Changed
- Updated application logo
- Updated documentation with all supported CLIs

### Fixed
- Fixed i18n JavaScript syntax error

### Added
- Integrated Sparkle auto-updater

## [1.3.0-beta.1] - 2026-02-25

### Added
- Added support for GitHub Copilot CLI
- Added support for Gemini CLI
- Added support for Aider
- Improved notification settings
