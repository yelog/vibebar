# VibeBar

[English](README.md) · [中文](README_zh.md) · [日本語](README_ja.md) · **[한국어](README_ko.md)**

VibeBar는 **Claude Code**, **Codex**, **OpenCode**의 TUI 세션 상태를 실시간으로 모니터링하는 경량 macOS 메뉴 바 앱입니다.

<img src="docs/images/vibebar.png" alt="VibeBar 스크린샷" width="600" />

아이콘 스타일과 색상 테마를 여러 가지 제공하며, 설정에서 원하는 대로 변경할 수 있습니다.

<img src="docs/images/vibebar-setting.png" alt="VibeBar 설정 화면 스크린샷" width="600" />

## 연동 방법 (중요)

- **Claude Code**: VibeBar 플러그인 사용을 권장합니다.
- **OpenCode**: VibeBar 플러그인 사용을 권장합니다.
- **Codex**: 이 저장소에는 Codex용 플러그인 체계가 없으므로 `vibebar` 래퍼 사용을 권장합니다.
- `vibebar` 래퍼는 `claude` / `opencode`도 지원하지만, 이 두 도구는 플러그인 연동이 우선입니다.

## 주요 기능

- 여러 세션과 도구의 상태를 메뉴 바에서 실시간으로 확인.
- 세션 상태: `running`(실행 중), `awaiting_input`(입력 대기), `idle`(유휴), `stopped`(중지), `unknown`(알 수 없음).
- 3가지 데이터 채널로 안정적인 감지 보장:
  - PTY 래퍼 (`vibebar`)
  - `vibebar-agent`를 통한 로컬 플러그인 이벤트
  - `ps` 프로세스 스캔 폴백
- Claude/OpenCode 플러그인 관리(설치·제거·업데이트)를 앱 내에서 바로 처리.
- `vibebar` 래퍼 명령도 앱 내에서 관리 가능.
- 아이콘 스타일·색상 테마 변경, 로그인 시 자동 시작, 업데이트 자동 확인 지원.
- 다국어 UI (`English`, `中文`, `日本語`, `한국어`).

## 프로젝트 구조

- `VibeBarCore`: 핵심 모델, 저장소, 집계, 스캐너, 플러그인/래퍼 감지.
- `VibeBarApp`: macOS 메뉴 바 앱 및 설정 UI.
- `VibeBarCLI` (`vibebar`): 대상 CLI를 감싸는 PTY 래퍼.
- `VibeBarAgent` (`vibebar-agent`): 플러그인 이벤트를 받는 로컬 Unix 소켓 서버.
- `plugins/*`: Claude/OpenCode 플러그인 패키지.

## 세션 감지 원리

VibeBar는 3가지 채널의 데이터를 통합하여 상태를 판단합니다.

1. `vibebar` PTY 래퍼: 높은 정확도의 인터랙션 상태 수집.
2. `vibebar-agent` 소켓 이벤트: 플러그인 생명주기 및 상태 업데이트.
3. `ps` 스캔 폴백: 상위 채널을 사용할 수 없을 때 프로세스 기반으로 세션 탐지.

도구 레벨 상태 우선순위:

`running > awaiting_input > idle > stopped > unknown`

런타임 데이터 경로:

- 세션 파일: `~/Library/Application Support/VibeBar/sessions/*.json`
- Agent 소켓: `~/Library/Application Support/VibeBar/runtime/agent.sock`

## 설치

### 방법 A: 앱 다운로드 (권장)

1. [GitHub Releases](https://github.com/yelog/VibeBar/releases)에서 최신 `VibeBar-*-universal.dmg` 다운로드.
2. `VibeBar.app`을 `응용 프로그램` 폴더로 드래그.
3. 첫 실행 시 앱을 우클릭한 뒤 **열기** 선택 (Gatekeeper 우회).

### 방법 B: 소스 빌드

필요 환경: macOS 13 이상, Xcode Command Line Tools, Swift 6.2.

```bash
swift build
```

## 빠른 시작 (소스 빌드)

1. 앱 실행:

```bash
swift run VibeBarApp
```

2. Agent 실행 (플러그인 이벤트 수신을 위해 권장):

```bash
swift run vibebar-agent --verbose
```

3. Claude/OpenCode용 로컬 플러그인 설치:

```bash
bash scripts/install/setup-local-plugins.sh
```

4. 래퍼로 Codex 실행 (권장):

```bash
swift run vibebar codex -- --model gpt-5-codex
```

5. 폴백: 플러그인을 사용할 수 없을 때 래퍼로 Claude/OpenCode 실행:

```bash
swift run vibebar claude
swift run vibebar opencode
```

플러그인 문서:

- `plugins/README.md`
- `plugins/claude-vibebar-plugin/README.md`
- `plugins/opencode-vibebar-plugin/README.md`

## 개발 명령어

```bash
# 빌드
swift build
swift build -c release

# 실행
swift run VibeBarApp
swift run vibebar-agent --verbose
swift run vibebar codex

# 테스트 (플레이스홀더)
swift test
```

universal `.dmg` 패키징:

```bash
bash scripts/build/package-app.sh
```

## 문제 해결

- **메뉴 바 아이콘이 표시되지 않음**: 헤드리스 환경이나 SSH가 아닌 로컬 macOS GUI 세션인지 확인하세요.
- **오래된 세션이 남아 있음**: 메뉴에서 **Purge Stale**을 눌러 정리하고, 위의 세션 파일 경로도 확인하세요.
- **플러그인 이벤트가 수신되지 않음**: `vibebar-agent`가 실행 중인지 확인하고 소켓 경로를 점검하세요:

```bash
swift run vibebar-agent --print-socket-path
```

## 현재 제한 사항

- 플러그인 없이 사용할 경우, 입력 대기 상태 감지는 휴리스틱에 의존하므로 정확도에 한계가 있습니다.
- Codex는 아직 플러그인 이벤트 채널을 지원하지 않습니다.
- 자동화 테스트 커버리지는 아직 미흡합니다.
