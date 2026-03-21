# VibeBar

[English](README.md) · [中文](README_zh.md) · **[日本語](README_ja.md)** · [한국어](README_ko.md)

VibeBar は、**Claude Code**・**Codex**・**OpenCode**・**Aider**・**Gemini CLI**・**GitHub Copilot** の TUI セッション状態をリアルタイムで監視できる、軽量な macOS メニューバーアプリです。

<table>
  <tr>
    <th>エージェントセッションとトークン使用推移</th>
    <th>エージェントセッションとトークン使用推移</th>
  </tr>
  <tr>
    <td>
      <img src="docs/images/vibebar-light.png" />
    </td>
    <td>
      <img src="docs/images/vibebar-dark.png" />
    </td>
  </tr>
</table>

アイコンスタイルやカラーテーマは複数用意されており、設定画面から自由にカスタマイズできます。

<img src="docs/images/vibebar-setting.png" alt="VibeBar 設定画面のスクリーンショット" width="600" />

## 連携方法（重要）

- **Claude Code**：VibeBar プラグインの利用を推奨します。
- **OpenCode**：VibeBar プラグインの利用を推奨します。
- **Aider**：`vibebar` ラッパーの利用を推奨します。オプションで `vibebar notify` を使用し、入力待ち信号を改善できます。
- **Gemini CLI**：`vibebar` ラッパーの利用を推奨します。ヘッドレス/プロンプトモードでは、ラッパーが自動的に `--output-format stream-json` を有効にします（既に設定されている場合を除く）。
- **GitHub Copilot**：VibeBar Hooks プラグインの利用を推奨します。**設定 → プラグイン → GitHub Copilot → インストール** から操作してください。VibeBar は現在実行中のすべての Copilot セッションのプロジェクトディレクトリに `.github/hooks/hooks.json` を自動展開します。インストール後に新たに開いたプロジェクトは、再度**インストール**をクリックするか手動でファイルをコピーしてください。
- **Codex**：このリポジトリには Codex 向けのプラグイン機構がないため、`vibebar` ラッパーの利用を推奨します。
- `vibebar` ラッパーは `claude` / `codex` / `opencode` / `aider` / `gemini` / `copilot` に対応していますが、これらのツールはプラグイン連携が優先されます。

## 機能

- 複数セッション・複数ツールの状態をメニューバーでリアルタイム確認。
- ノッチ付き MacBook では任意でノッチ表示モードを有効化でき、ノッチ右側に小さな黒いアイコン領域を延長表示します。現在のメインディスプレイが非対応の場合は通常のメニューバー入口へ自動で戻ります。
- セッション状態：`running`（実行中）、`awaiting_input`（入力待ち）、`idle`（待機中）、`stopped`（停止）、`unknown`（不明）。
- 3 系統のデータチャネルで信頼性を確保：
  - PTY ラッパー（`vibebar`）
  - `vibebar-agent` 経由のローカルプラグインイベント
  - `ps` プロセススキャンによるフォールバック
- Claude Code、OpenCode、GitHub Copilot のプラグイン管理（インストール・アンインストール・更新）をアプリ内で完結。
- `vibebar` ラッパーコマンドもアプリ内から管理可能。
- アイコンスタイル・カラーテーマの切り替え、ログイン時起動、アップデート自動確認に対応。
- 多言語 UI（`English`・`中文`・`日本語`・`한국어`）。

## トークン使用量の追跡

VibeBar は、対応する AI ツール間でのトークン使用量を追跡し、詳細な分析と可視化を提供します：

**対応ツール：**
- **Claude Code** — `~/.config/claude/projects/*/usage.jsonl` から読み取り
- **Codex** — `~/.codex/sessions/*/usage.jsonl` から読み取り
- **OpenCode** — `~/.local/share/opencode/opencode.db` から読み取り

**トークン指標：**
- 入力トークン、出力トークン
- キャッシュ読み取りトークン、キャッシュ書き込みトークン
- 総トークン数と推定コスト（USD）

**可視化オプション：**
- **GitHub スタイルのヒートマップ** — 色の濃さで使用量を示す 39 週間のアクティビティマトリックス
- **棒グラフ** — 時間帯ごとの積み上げ棒グラフ
- **折れ線グラフ** — 使用量トレンドを示す折れ線グラフ

**設定オプション：**
- **トークン**または**コスト**ビューの切り替え
- 粒度の調整：時間 / 日 / 週 / 月
- グループ化：ツール / モデル / なし
- 更新間隔の設定：5分 / 15分 / 30分 / 1時間
- 表示する最大シリーズ数のカスタマイズ

メニューバーのドロップダウンから、AI の使用パターンとコスト概要を一目で確認できます。

## プロジェクト構成

- `VibeBarCore`：コアモデル、ストレージ、集計、スキャナー、プラグイン/ラッパー検出。
- `VibeBarApp`：macOS メニューバーアプリと設定 UI。
- `VibeBarCLI`（`vibebar`）：対象 CLI の PTY ラッパー。
- `VibeBarAgent`（`vibebar-agent`）：プラグインイベント受信用のローカル Unix ソケットサーバー。
- `plugins/*`：Claude Code、OpenCode、GitHub Copilot Hooks のプラグインパッケージ。

## セッション検出の仕組み

VibeBar は以下の 3 系統のデータを統合して状態を判定します。

1. `vibebar` PTY ラッパー：高精度なインタラクション状態の取得。
2. `vibebar-agent` ソケットイベント：プラグインのライフサイクルと状態通知。
3. `ps` スキャンフォールバック：上位ソースが利用できない場合のプロセスベース検出。

ツールレベルの状態優先順位：

`running > awaiting_input > idle > stopped > unknown`

実行時のデータパス：

- セッションファイル：`~/Library/Application Support/VibeBar/sessions/*.json`
- Agent ソケット：`~/Library/Application Support/VibeBar/runtime/agent.sock`

## インストール

### 方法 A：アプリをダウンロード（推奨）

1. [GitHub Releases](https://github.com/yelog/VibeBar/releases) から最新の `VibeBar-*-universal.dmg` をダウンロード。
2. `VibeBar.app` を「アプリケーション」フォルダにドラッグ。
3. 初回起動時は右クリックして**「開く」**を選択（Gatekeeper 対応）。

### 方法 B：Homebrew

このリポジトリを tap として追加してインストール：

```bash
brew tap yelog/vibebar https://github.com/yelog/vibebar.git
brew install --cask yelog/vibebar/vibebar
```

**アップグレード：**

```bash
brew upgrade --cask yelog/vibebar/vibebar
```

### 方法 C：ソースからビルド

必要環境：macOS 13 以降、Xcode Command Line Tools、Swift 6.2。

```bash
swift build
```

## クイックスタート（ソースビルド）

1. アプリを起動：

```bash
swift run VibeBarApp
```

2. Agent を起動（プラグインイベント受信のため推奨）：

```bash
swift run vibebar-agent --verbose
```

3. Claude/OpenCode 用のローカルプラグインをインストール：

```bash
bash scripts/install/setup-local-plugins.sh
```

4. GitHub Copilot Hooks プラグインをインストール（Copilot を使用する場合）：

**VibeBar 設定 → プラグイン → GitHub Copilot → インストール** を開きます。VibeBar が `hooks.json` を現在実行中のすべての Copilot プロジェクトディレクトリに自動展開します。

5. ラッパー経由で Codex を起動（推奨）：

```bash
swift run vibebar codex -- --model gpt-5-codex
```

6. ラッパー経由で Aider を起動（推奨）：

```bash
swift run vibebar aider -- --model sonnet
```

7. オプション：Aider の通知を VibeBar の状態更新に転送：

```bash
aider --notifications --notifications-command "vibebar notify aider awaiting_input"
```

8. ラッパー経由で Gemini CLI を起動：

```bash
swift run vibebar gemini -p "explain this codebase"
```

Gemini のプロンプト/ヘッドレス呼び出し（`-p`、`--prompt`、`--stdin`、または非 TTY stdin）では、`vibebar` が自動的に `--output-format stream-json` を追加します（既に `--output-format` を指定している場合を除く）。

Gemini hooks 統合例（`.gemini/settings.json`）：

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "vibebar notify gemini session_start session_id=$GEMINI_SESSION_ID" }]
    }],
    "AfterAgent": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "vibebar notify gemini after_agent session_id=$GEMINI_SESSION_ID" }]
    }],
    "SessionEnd": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "vibebar notify gemini session_end session_id=$GEMINI_SESSION_ID" }]
    }]
  }
}
```

9. フォールバック：プラグインが使えない場合、ラッパー経由で Claude/OpenCode を起動：

```bash
swift run vibebar claude
swift run vibebar opencode
```

プラグインのドキュメント：

- `plugins/README.md`
- `plugins/claude-vibebar-plugin/README.md`
- `plugins/opencode-vibebar-plugin/README.md`
- `plugins/copilot-vibebar-hooks/README.md`

## 開発用コマンド

```bash
# ビルド
swift build
swift build -c release

# 実行
swift run VibeBarApp
swift run vibebar-agent --verbose
swift run vibebar codex

# テスト（プレースホルダー）
swift test
```

universal `.dmg` のパッケージング：

```bash
bash scripts/build/package-app.sh
```

## トラブルシューティング

- **メニューバーにアイコンが表示されない**：ヘッドレス環境や SSH 接続ではなく、ローカルの macOS GUI セッションであることを確認してください。
- **古いセッションが残っている**：メニューの **Purge Stale** で削除し、上記のセッションファイルパスも確認してください。
- **プラグインイベントが届かない**：`vibebar-agent` が起動しているか確認し、ソケットパスをチェックしてください：

```bash
swift run vibebar-agent --print-socket-path
```

## 現時点での制限事項

- プラグインなしの場合、入力待ち状態の検出はヒューリスティックに依存するため精度に限界があります。
- Codex はプラグインイベントチャネルに未対応です。
- Aider はこのリポジトリでネイティブプラグインイベントチャネルを持っていません。`--notifications-command` 経由で `vibebar notify` を使用することで、入力待ち検出を改善できます。
- Gemini CLI のトランスクリプト解析は補助的なものです。hooks/プロセス検出を補強するものであり、プライマリなリアルタイムソースとして扱わないでください。
- GitHub Copilot Hooks はリポジトリ単位での設定が必要です。各プロジェクトの `.github/hooks/` ディレクトリに `hooks.json` が必要です。VibeBar は**インストール**時に自動展開しますが、インストール後に新たに開いたプロジェクトは再度**インストール**をクリックするか手動でファイルをコピーしてください。
- 自動テストはまだ最小限の実装にとどまっています。

## 謝辞

このプロジェクトは [ccusage](https://github.com/ryoppippi/ccusage) にインスパイアされました。[@ryoppippi](https://github.com/ryoppippi) さんの素晴らしいアイデアと実装に感謝します。
