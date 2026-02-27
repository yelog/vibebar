# VibeBar

[English](README.md) · [中文](README_zh.md) · **[日本語](README_ja.md)** · [한국어](README_ko.md)

VibeBar は、**Claude Code**・**Codex**・**OpenCode**・**GitHub Copilot** の TUI セッション状態をリアルタイムで監視できる、軽量な macOS メニューバーアプリです。

<img src="docs/images/vibebar.png" alt="VibeBar スクリーンショット" width="600" />

アイコンスタイルやカラーテーマは複数用意されており、設定画面から自由にカスタマイズできます。

<img src="docs/images/vibebar-setting.png" alt="VibeBar 設定画面のスクリーンショット" width="600" />

## 連携方法（重要）

- **Claude Code**：VibeBar プラグインの利用を推奨します。
- **OpenCode**：VibeBar プラグインの利用を推奨します。
- **GitHub Copilot**：VibeBar Hooks プラグインの利用を推奨します。**設定 → プラグイン → GitHub Copilot → インストール** から操作してください。VibeBar は現在実行中のすべての Copilot セッションのプロジェクトディレクトリに `.github/hooks/hooks.json` を自動展開します。インストール後に新たに開いたプロジェクトは、再度**インストール**をクリックするか手動でファイルをコピーしてください。
- **Codex**：このリポジトリには Codex 向けのプラグイン機構がないため、`vibebar` ラッパーの利用を推奨します。
- `vibebar` ラッパーは `claude` / `opencode` / `copilot` にも対応していますが、これらのツールはプラグイン連携が優先されます。

## 機能

- 複数セッション・複数ツールの状態をメニューバーでリアルタイム確認。
- セッション状態：`running`（実行中）、`awaiting_input`（入力待ち）、`idle`（待機中）、`stopped`（停止）、`unknown`（不明）。
- 3 系統のデータチャネルで信頼性を確保：
  - PTY ラッパー（`vibebar`）
  - `vibebar-agent` 経由のローカルプラグインイベント
  - `ps` プロセススキャンによるフォールバック
- Claude Code、OpenCode、GitHub Copilot のプラグイン管理（インストール・アンインストール・更新）をアプリ内で完結。
- `vibebar` ラッパーコマンドもアプリ内から管理可能。
- アイコンスタイル・カラーテーマの切り替え、ログイン時起動、アップデート自動確認に対応。
- 多言語 UI（`English`・`中文`・`日本語`・`한국어`）。

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

### 方法 B：ソースからビルド

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

6. フォールバック：プラグインが使えない場合、ラッパー経由で Claude/OpenCode を起動：

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
- GitHub Copilot Hooks はリポジトリ単位での設定が必要です。各プロジェクトの `.github/hooks/` ディレクトリに `hooks.json` が必要です。VibeBar は**インストール**時に自動展開しますが、インストール後に新たに開いたプロジェクトは再度**インストール**をクリックするか手動でファイルをコピーしてください。
- 自動テストはまだ最小限の実装にとどまっています。
