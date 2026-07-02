# gitkun

macOS のメニューバーに常駐し、GitHub の未読通知と「自分にレビュー依頼が来ている未マージ PR」を
定期的にチェックする個人用の軽量ユーティリティ。加えて、自分が assignee / author の open PR
（My PRs）と、自分にアサインされている open Issue（Assigned Issues）もメニューから参照できる。

- 未読通知・未レビュー PR の有無に応じてメニューバーアイコンが4通りに切り替わる
- 新規の未読通知・新規レビュー依頼があれば macOS 通知バナー + サウンドで知らせる（My PRs /
  Assigned Issues は通知しない）
- メニュー項目クリックでブラウザが開く。既定ブラウザが Safari / Chrome 系なら、同じ PR / Issue を
  表示している既存タブがあればそれをアクティブにする（新規タブを増やさない）
- draft PR・タイトル先頭 `[WIP]`・`wip` ラベルの PR は Review Requests から除外（設定で ON/OFF 可）
- 約1時間ごとに自リポジトリの最新リリースを確認し、新バージョンがあればメニューから自己更新できる

## 動作要件

- macOS 13 Ventura 以降
- Swift toolchain（`swift build` / `swift test` が使えること。Xcode 本体は不要、Command Line
  Tools があれば良い）
- [gh CLI](https://cli.github.com/) がインストール済み・ログイン済みであること

```bash
brew install gh
gh auth login
```

## インストール

### リリース版を使う（推奨）

1. [Releases](https://github.com/m-tkg/gitkun/releases) から最新の `gitkun.zip` をダウンロードして展開
2. `gitkun.app` を `/Applications` へコピーして起動
3. 初回起動時に通知の許可ダイアログが出たら「許可」を選択
4. ブラウザの既存タブ再利用機能を使う場合、システム設定 > プライバシーとセキュリティ >
   オートメーション で Safari / Chrome 系ブラウザの制御を許可する

配布版は Developer ID 署名 + 公証済み（詳細は [`docs/SIGNING.md`](docs/SIGNING.md)）。

### ソースからビルドする

Xcode は使わず Swift Package Manager + `Scripts/bundle.sh` でビルドする。

```bash
swift build                       # ビルド（Debug）
swift test                        # ユニットテスト（gitkunCoreTests）
bash Scripts/bundle.sh release    # .app を組み立て（Release・ad-hoc 署名）
open gitkun.app
```

## メニュー構成

クリックするとメニューバーアイコンからメニューが開く。通知は `reason` を集約カテゴリ
（Review Requested / Mentioned / Commented / State Changed / Authored など）ごとにサブメニュー化し、
それ以外のセクションも件数付きのサブメニューで一覧を表示する。

```
gitkun v1.12.1                    ← 現在バージョン（操作不可）
────────────────────
Review Requested (1) ▶            ← 通知カテゴリ（サブメニュー）
Mentioned (2) ▶
Commented (3) ▶
...
────────────────────
Review Requests (N) ▶             ← レビュー依頼中の PR
My PRs (N) ▶                      ← assignee:@me + author:@me
Assigned Issues (N) ▶             ← assignee:@me の Issue
────────────────────
Status ▶                          ← サブメニュー
  Status: OK
  Version: 1.12.1
  Unread: 2
  Review requests: 1
  My PRs: 3
  Assigned issues: 1
  Last checked: 23:45
────────────────────
Refresh                           ← 手動更新（フェッチ中は無効）
Check for Updates…                ← 更新があれば "⬆ Update to vX.Y.Z…" に切り替わる
Settings…                         ← 設定ウィンドウを開く（⌘,）
────────────────────
Quit                              ← ⌘Q
```

各サブメニューの行はリポジトリ名・タイトル・相対時刻を表示し、クリックでブラウザに該当ページを
開く（通知だけはクリック時に refresh も実行される）。一覧からの即時削除はせず、次回ポーリング
または Refresh で更新される。

## 設定

メニューの `Settings…` から以下を変更できる（`AppState` / `LocalStore` が `UserDefaults` を共有）。

- 未読通知・レビュー依頼それぞれの通知音（先頭の `N/A` を選ぶとそのイベントの音だけ鳴らさない）
- draft / WIP PR を Review Requests から除外するか（デフォルト ON）
- Launch at login（ログイン時の自動起動）

ポーリング間隔（デフォルト30秒）は UI 未実装で、`UserDefaults` の `pollingInterval` キーを直接
変更する必要がある。

## 開発

```bash
swift build                                   # ビルド（Debug）
swift test                                    # ユニットテスト
bash Scripts/bundle.sh release                # .app を組み立て（Release・ad-hoc 署名）

# ローカル検証用（本番と TCC 権限を分離した「gitkun (Local)」を生成して起動）
pkill -x gitkun 2>/dev/null; LOCAL=1 bash Scripts/bundle.sh debug && open "gitkun (Local).app"

swift package clean; rm -rf .build "gitkun.app" "gitkun (Local).app"  # 成果物削除
```

テスト対象は `Sources/gitkunCore/`（AppKit 非依存の純粋ロジック）のみ。`Sources/gitkun/`
（AppKit・Combine・SwiftUI に依存する実行ファイル本体）はテストから除外されており、`swift test`
実行時に GitHub ポーリングや通知許可ダイアログは発生しない。

ブランチ運用・リリース手順・署名/公証の詳細は [`CLAUDE.md`](CLAUDE.md) を参照。

## アーキテクチャ概要

```
Sources/gitkunCore/     純粋ロジック（gitkun ターゲットからも Tests からも参照）
├── AppError.swift              エラー種別
├── AppStatus.swift             ステータス種別・ポーリング間隔ポリシー
├── FetchDiff.swift             新規差分判定・My PRs マージ
├── FetchErrors.swift           複数フェッチのエラー集約
├── GitHubNotification.swift    通知モデル・reason/subject.type 定義
├── GitHubTabMatcher.swift      ブラウザ既存タブの URL 同一判定
├── MenuBarIcon.swift           未読/未レビューからアイコン名を導出
├── MenuRowDisplayable.swift    メニュー行・通知バナー共通プロトコル
├── NotificationGrouping.swift  通知のカテゴリ集約・表示順
├── RelativeTime.swift          相対時刻フォーマット
├── ReleaseInfo.swift           リリース情報モデル
├── SearchModels.swift          Search API モデル（UnreviewedPR / AssignedItem）
├── SystemSoundNames.swift      システムサウンド名の抽出
├── URLResolver.swift           通知 API URL → Web URL 変換
└── VersionComparator.swift     タグ ⇔ CFBundleShortVersionString 比較

Sources/gitkun/         実行ファイル本体（AppKit / Combine / SwiftUI 依存）
├── gitkunApp.swift             @main、二重起動防止
├── AppDelegate.swift           NSStatusItem 管理、アイコン切り替え、Kuntraykun 連携配線
├── AppDelegate+Menu.swift      NSMenu 構築
├── AppDelegate+Actions.swift   メニューアクション（Refresh / Settings / 更新チェック等）
├── AppState.swift              状態管理・フェッチのオーケストレーション・通知発火
├── GitHubNotificationService.swift  gh CLI 実行、トークンキャッシュ、各種フェッチ
├── ProcessRunner.swift         外部コマンド実行の共通ランナー
├── BrowserTabOpener.swift      既定ブラウザの既存タブ再利用（AppleScript）
├── Poller.swift                Timer ラッパー
├── SelfUpdater.swift           自己更新（zip 取得・展開・.app 入れ替え）
├── LocalStore.swift            UserDefaults ラッパー
├── UserNotifier.swift          UNUserNotificationCenter
├── LaunchAtLoginManager.swift  SMAppService
├── NotificationMenuItemView.swift  メニュー行カスタムビュー
├── SettingsView.swift          設定画面（SwiftUI）
├── KuntraykunBridge.swift      kuntraykun 連携（アイコン集約・メニュー委譲）
└── KuntraykunIconExport.swift  現在アイコンの PNG 書き出し（kuntraykun 一覧用）
```

## ログ確認

エラー時は Console.app で詳細ログを確認できる。

```
subsystem == "com.mtkg.gitkun"
```

またはメニューの Status サブメニューから「Open Console.app」で起動し、「Copy Error」でエラー
詳細をクリップボードにコピー可能。
