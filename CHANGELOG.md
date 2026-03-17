# Changelog

All notable changes to VibeBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.4] - 2026-03-17

### Added
- add GitHub star promotion in About settings
- add Homebrew cask support
- add Homebrew cask support for VibeBar installation
- add animated window resize on tab switch
- add chart hover tooltips
- add enable/disable toggle for token usage feature
- add full refresh interval setting and fix working directory extraction
- add hour granularity option for bar and line charts
- add icons to distinguish update time and load duration
- add incremental loading with periodic full refresh
- add internationalization for usage settings and menu
- add metric selector for github heatmap
- add next refresh countdown in settings
- add project-based grouping for token usage statistics
- add token usage analytics
- adjust window heights for appearance and about tabs
- detach usage chart tooltip
- display load duration and use relative time format
- improve refresh controls with independent loading states
- increase About tab window height to 720
- increase Appearance tab window width by 100
- integrate LiteLLM pricing data for accurate model cost calculation
- limit chart to 10 buckets based on granularity
- show top 7 models instead of 5 in chart grouping
- update usage refresh cadence labels and add refresh time tracking

### Changed
- add Aider and Gemini CLI support with dual-mode screenshots
- add Token Usage Tracking section to all language READMEs
- add time-range filtering to usage loaders
- adjust chart and heatmap layout
- cache buckets by (granularity, grouping, sources)
- decouple display settings from snapshot
- format token count with appropriate units in chart footer
- make tooltip float over chart instead of reserving space
- optimize chart styling and refresh logic
- optimize grouping switch and add loading indicator
- optimize visualization style switching performance
- set appearance tab width to 550
- simplify view modifiers and remove background fill
- skip legacy JSON file scanning in OpenCode loader
- unify usage tab window width with general tab
- use adaptive grid layout for usage settings

### Fixed
- add 'ago' suffix to last refresh time for clarity
- add horizontal padding to settings section titles
- adjust bar chart height based on daily token usage total
- adjust usage settings grid and fix title clipping
- adjust usage settings layout to fix asymmetric padding
- align settings section title with card content
- correct working directory extraction from Claude Code project paths
- display relative time with appropriate units in menu
- don't show error dialog when already up to date
- enlarge menu github heatmap
- ensure full refresh clears all caches including file cache
- fix UsageBarChartView Y-axis scale to dynamically adjust based on data max value
- fix working directory extraction and incremental loader cache usage
- improve dark mode heatmap contrast
- improve footer tooltip positioning and style
- improve icon style change responsiveness
- improve multi-series chart distinction
- increase usage settings width by 30px
- lift preview chart tooltip
- make empty heatmap cells visible
- make menu content fill full width
- make session menu items fill full menu width
- normalize OpenCode timestamps and compact tooltips
- optimize incremental loading performance
- place chart tooltips above legends
- preserve loadDuration when rebuilding snapshot from cache
- preserve updatedAt and loadDuration when using cache
- prevent settings window horizontal overflow
- read opencode tokens from sqlite
- reduce usage settings window width to fit chart
- remove center alignment causing asymmetric padding in usage settings
- remove duplicate time display in settings preview
- remove negative padding causing left clipping
- respect metric selection in github heatmap
- skip OpenCode legacy JSON files without modelID
- sync chart grouping with current settings
- update chart immediately when changing grouping/granularity
- use dashed hover guide
- 修复启动后刷新时间显示不正确的问题
- 修复增量刷新时图表不显示当天数据的问题
- 修复多次重启后刷新时间显示错误的问题
- 修复部分全量部分增量刷新时时间不更新的问题

## [1.3.4-beta.3] - 2026-03-16

### Added
- detach usage chart tooltip
- integrate LiteLLM pricing data for accurate model cost calculation
- add hour granularity option for bar and line charts
- add incremental loading with periodic full refresh
- add icons to distinguish update time and load duration
- display load duration and use relative time format
- add internationalization for usage settings and menu

### Changed
- cache buckets by (granularity, grouping, sources)
- optimize visualization style switching performance
- set appearance tab width to 550
- skip legacy JSON file scanning in OpenCode loader
- unify usage tab window width with general tab

### Fixed
- fix UsageBarChartView Y-axis scale to dynamically adjust based on data max value
- use dashed hover guide
- lift preview chart tooltip
- preserve updatedAt and loadDuration when using cache
- add 'ago' suffix to last refresh time for clarity
- improve multi-series chart distinction
- improve icon style change responsiveness
- make empty heatmap cells visible
- improve dark mode heatmap contrast
- skip OpenCode legacy JSON files without modelID
- sync chart grouping with current settings
- remove duplicate time display in settings preview
- optimize incremental loading performance
- preserve loadDuration when rebuilding snapshot from cache
- display relative time with appropriate units in menu

## [1.3.4-beta.2] - 2026-03-15

### Added
- Token usage analytics with chart hover tooltips
- Enable/disable toggle for token usage feature
- Metric selector for GitHub heatmap
- Show top 7 models instead of 5 in chart grouping
- Limit chart to 10 buckets based on granularity
- Homebrew cask support
- Increase Appearance tab window width by 100px

### Changed
- Use adaptive grid layout for usage settings
- Make tooltip float over chart instead of reserving space
- Add time-range filtering to usage loaders (performance)
- Optimize grouping switch and add loading indicator
- Decouple display settings from snapshot
- Optimize chart styling and refresh logic
- Format token count with appropriate units in chart footer
- Simplify view modifiers and remove background fill

### Fixed
- Remove center alignment causing asymmetric padding in usage settings
- Align settings section title with card content
- Adjust usage settings layout to fix asymmetric padding and title clipping
- Add horizontal padding to settings section titles
- Increase usage settings width by 30px and reduce window width to fit chart
- Remove negative padding causing left clipping
- Make session menu items and menu content fill full width
- Place chart tooltips above legends
- Adjust chart and heatmap layout
- Enlarge menu GitHub heatmap
- Prevent settings window horizontal overflow
- Improve footer tooltip positioning and style
- Respect metric selection in GitHub heatmap
- Update chart immediately when changing grouping/granularity
- Read OpenCode tokens from SQLite
- Normalize OpenCode timestamps and compact tooltips

## [1.3.4-beta.1] - 2026-03-09

### Added
- add GitHub star promotion in About settings
- add animated window resize on tab switch

### Changed
- adjust window heights for appearance and about tabs
- increase About tab window height to 720

## [1.3.4-beta.0] - 2026-03-08

### Fixed
- Don't show error dialog when already up to date

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
