# CLAUDE.md

## プロジェクト概要

gitkun は、macOS のメニューバーに常駐し、GitHub の未読通知と「レビュアーとして自分に review request が来ている未マージ PR」を定期的にチェックして、新規分をユーザーに知らせる軽量なユーティリティアプリである。加えて、自分が assignee または author の open PR（My PRs）と、自分にアサインされている open Issue の一覧をメニューから参照できる。

個人利用を前提とした MVP とし、シンプルで安定した動作を最優先とする。

---

## 前提条件

- macOS 13 Ventura 以降
- Xcode がインストール済みであること
- `gh` CLI がインストール済みであること（`/opt/homebrew/bin/gh` または `/usr/local/bin/gh`）
- `gh auth login` が完了していること
- App Store 配布や sandbox 制約は考慮しない

---

## 技術スタック

- Swift 5.0
- AppKit（NSStatusItem、NSMenu、NSPopover、アイコン切り替え、音声再生、ブラウザ起動）
- SwiftUI（gitkunApp.swift の Settings シーンのみ）
- async/await + Combine
- OSLog（ロギング）

対応OSは macOS 13+ のみ。後方互換性は考慮しない。

---

## ビルド・実行

```bash
# Debug ビルド & 起動（既存プロセスを終了してから起動）
make run

# Debug ビルドのみ
make debug

# Release ビルド
make release

# ビルド成果物削除
make clean
```

---

## 機能要件

### 基本機能

- メニューバーに常駐するアプリ
- 二重起動防止（同じ Bundle ID が起動中なら即終了）
- macOS 起動時に自動起動可能（Launch at login）
- GitHub の未読通知・未レビュー PR・自分の PR（assignee + author マージ）・自分アサインの Issue を定期取得（4 本並行フェッチ）
- 新規未読 / 新規レビュー依頼があれば macOS 通知バナー + 音（My PRs / Assigned Issues は通知しない）
- メニューから通知一覧、レビュー依頼一覧、My PRs / Assigned Issues 一覧を表示
- 項目クリックでブラウザ遷移 + リストから即削除（次ポーリングで再取得）
- **未読/未レビューの組み合わせに応じてメニューバーアイコンが4通りに切り替わる**（My PRs / Assigned Issues はアイコン状態に影響しない）

---

## GitHub データ取得

### 通知コマンド

```
gh api /notifications?per_page=50&all=false
```

### 未レビュー PR コマンド

```
gh api "/search/issues?q=is:open+is:pr+review-requested:@me&per_page=50"
```

### My PRs / Assigned Issues コマンド

```
# assignee:@me（PR + Issue 混在）
gh api "/search/issues?q=is:open+assignee:@me&per_page=50"

# author:@me（PR のみ）
gh api "/search/issues?q=is:open+is:pr+author:@me&per_page=50"
```

assignee 側のレスポンスを `pull_request` フィールド有無で PR/Issue に分類し、PR は author 側の結果と `id` でユニオン（重複排除）して `updatedAt` 降順にソート、上限 50 件で My PRs に格納する。Issue は assignee 側だけを使う。

Search API は `{ "items": [...] }` 形式。`repository` オブジェクトを含まないため、各 item の `repository_url`（`https://api.github.com/repos/{owner}/{repo}`）から `owner/repo` を導出する。

**注意:** `-F` フラグを使うと `gh api` が GET → POST に変わり 404 になるため、クエリパラメータは URL に直接含める。

### 実装要件

- `Process` で `gh` を実行
- `gh` パスは以下を順に探索
  - `/opt/homebrew/bin/gh`
  - `/usr/local/bin/gh`
- 起動時に `gh auth token` でトークンを取得・キャッシュし、以降は `GH_TOKEN` 環境変数で渡す
  - GUI アプリから起動したサブプロセスが Keychain にアクセスできない問題を回避
  - トークンはアプリセッション中メモリにキャッシュ（再起動時に再取得）
- JSON をそのまま Swift でパース（`JSONDecoder`）
- jq など外部ツールには依存しない

### 取得範囲

- 通知: 未読のみ（`all=false`）、1ページのみ（最大50件）
- レビュー依頼: `is:open is:pr review-requested:@me` の検索結果、最大50件
- My PRs: `is:open assignee:@me` の PR と `is:open is:pr author:@me` の結果を `id` でユニオン、最大50件
- Assigned Issues: `is:open assignee:@me` のうち Issue（`pull_request` フィールドなし）のみ、最大50件

---

## ポーリング仕様

- デフォルト: 30秒
- 起動時に即フェッチ（`NotificationPoller.start()` が即時1回発火）
- 1ポーリングで通知・レビュー依頼・assignee:@me・author:@me を `async let` で並行フェッチ（4 本）
- ポーリング制御: `isFetching` フラグで同時実行を防止
- 一部の API が失敗しても、成功した分の結果は反映する（エラー詳細は `lastErrorDetail` に連結）
- My PRs は assignee / author の少なくとも片方が成功した場合に更新（両方失敗時は前回値を据え置き）、Assigned Issues は assignee 側成功時のみ更新

---

## 新規判定

### 通知

- デフォルト: `id` の差分で判定
- オプション: `updated_at` ベース（`DiffStrategy.updatedAt`）

### 未レビュー PR

- `id` の差分で判定のみ（`UnreviewedPR.id` は `Int`、キャッシュも `Set<Int>` で統一）

### My PRs / Assigned Issues

- 差分判定なし。毎ポーリングのフェッチ結果でそのまま上書き（My PRs は assignee + author を id dedupe → updatedAt 降順）。
- 通知バナー・音・アイコン変化は一切なし。

### 初回挙動

- 初回フェッチはベースラインのみ（`LocalStore.isFirstFetch` で管理。通知・レビュー依頼共通）
- 通知・音は出さない

---

## メニューバーアイコン

- 通常: テンプレート画像（`MenuBarIcon`、ライト/ダーク自動対応）
- **未読あり / 未レビューありの組み合わせでアイコンを切り替え**
  - `AppDelegate` が `appState.$hasUnread` と `appState.$hasUnreviewed` を `combineLatest` で監視し、`NSStatusItem.button?.image` を直接差し替え
  - `MenuBarExtra` は使用しない（ラベルが静的レンダリングのため動的更新不可）

| 未読 | 未レビュー | 使用アセット |
|---|---|---|
| × | × | `MenuBarIcon` |
| ○ | × | `MenuBarIconUnread` |
| × | ○ | `MenuBarIconUnreview` |
| ○ | ○ | `MenuBarIconUnreadAndUnreview` |

### アイコンアセット

- `gitkun/Assets.xcassets/AppIcon.appiconset/` — アプリアイコン（16〜1024px）
- `gitkun/Assets.xcassets/MenuBarIcon.imageset/` — 通常アイコン（template、16/32px）
- `gitkun/Assets.xcassets/MenuBarIconUnread.imageset/` — 未読ありアイコン（original、16/32px）
- `gitkun/Assets.xcassets/MenuBarIconUnreview.imageset/` — 未レビューありアイコン（original、16/32px）
- `gitkun/Assets.xcassets/MenuBarIconUnreadAndUnreview.imageset/` — 両方ありアイコン（original、16/32px）

---

## 通知仕様

### トリガー

- 新規未読が1件以上増えた場合（初回フェッチを除く）
- 新規レビュー依頼が1件以上増えた場合（初回フェッチを除く）

### 内容

- 通知: タイトル `"GitHub Notifications"`、本文 `"PR title (+N more)"`
- レビュー依頼: タイトル `"GitHub Review Requests"`、本文 `"PR title (+N more)"`

### クリック時

- 通知: `URLResolver` で API URL → Web URL に変換してブラウザで開く
- レビュー依頼: Search API が返す `html_url` をそのままブラウザで開く

---

## URL 解決

| API URL パターン | Web URL |
|---|---|
| `.../issues/{n}` | `.../issues/{n}` |
| `.../pulls/{n}` | `.../pull/{n}` |
| `.../commits/{sha}` | `.../commit/{sha}` |
| その他・null | `repository.htmlUrl` |

`URLResolver` は通知 (`GitHubNotification`) のみ使用。未レビュー PR は `html_url` を直接使う。

---

## メニューバー UI

通知セクションは `reason` で一次グルーピングする。グループは固定優先順（`NotificationReason.allCases` の宣言順）で並べ、未知 reason は末尾にアルファベット順で付ける。各ヘッダーに件数を併記。

```
GitHub Notifications
────────────────────
Mentioned (2)             ← disabled ヘッダー
● owner/repo              ← 緑の丸
  タイトル（1行）
  5m ago
● owner/repo2
  ...
────────────────────
Review Requested (1)
● owner/repo
  ...
────────────────────
Commented (3)
...
────────────────────
Review Requests           ← 別セクション（未レビュー PR）
────────────────────
● owner/repo              ← 橙の丸
  PR タイトル
  3h ago
────────────────────
My PRs (N)                ← 別セクション（assignee:@me + author:@me）
────────────────────
● owner/repo              ← 青の丸
  PR タイトル
  ...
────────────────────
Assigned Issues (M)       ← 別セクション
────────────────────
● owner/repo              ← 紫の丸
  Issue タイトル
  ...
────────────────────
Status ▶                 ← サブメニュー
  Status: OK
  Unread: X
  Review requests: Y
  My PRs: N
  Assigned issues: M
  Last checked: HH:mm
  [エラー詳細]            ← エラー時のみ
  [Copy Error]            ← エラー時のみ
  [Open Console.app]      ← エラー時のみ
────────────────────
Refresh                   ← フェッチ中は disabled
Launch at login: ON/OFF
────────────────────
Quit
```

### reason グルーピング優先順

`Models.swift` の `NotificationReason` 宣言順が優先度（小さいほど上）。
現在の順:
`mention` → `review_requested` → `approval_requested` → `assign` → `author` → `comment` → `state_change` → `ci_activity` → `push` → `team_mention` → `security_alert` → `subscribed` → `manual` → `invitation` → `member_feature_requested`。
GitHub が新しい reason を追加した場合は「その他」として末尾にアルファベット順で出る。

---

## ロギング

- `OSLog` / `Logger` を使用（subsystem: `com.mtkg.gitkun`）
- Console.app でフィルタ: `subsystem == "com.mtkg.gitkun"`
- ログ内容: `gh` パス・exit code・stderr・stdout プレビュー・取得件数（通知/未レビュー PR/assigned items/authored PRs）・パースエラー・アイコン切り替え

---

## 設定（UserDefaults）

| キー | 型 | デフォルト |
|---|---|---|
| `pollingInterval` | Int | 30 |
| `diffStrategy` | String | `"id"` |
| `soundEnabled` | Bool | `true` |
| `knownNotificationIDs` | [String] | `[]` |
| `knownNotificationUpdatedAts` | [String:String] | `[:]` |
| `knownUnreviewedPRIDs` | [String] | `[]` |

設定 UI（ポーリング間隔・差分方式・通知音）はメニューに未実装。`LocalStore` 経由で変更可能。

---

## アーキテクチャ

| ファイル | 役割 |
|---|---|
| `gitkunApp.swift` | `@main`、`NSApplicationDelegateAdaptor`、二重起動防止 |
| `AppDelegate.swift` | `NSStatusItem` 管理、`NSMenu` 構築、アイコン切り替え（Combine） |
| `AppState.swift` | `@MainActor ObservableObject`、状態管理、差分判定、通知発火（通知・未レビュー PR・My PRs / Assigned Issues の並行処理、PR は assignee + author マージ） |
| `GitHubNotificationService.swift` | `actor`、`gh` CLI 実行、トークンキャッシュ、通知・未レビュー PR・assignee 検索・author 検索のフェッチ |
| `NotificationPoller.swift` | `Timer` ポーリング、重複実行防止 |
| `LocalStore.swift` | `UserDefaults` ラッパー |
| `UserNotifier.swift` | `UNUserNotificationCenter`、通知クリックでブラウザ起動 |
| `LaunchAtLoginManager.swift` | `SMAppService`（macOS 13+） |
| `URLResolver.swift` | API URL → Web URL 変換（通知のみ） |
| `NotificationMenuItemView.swift` | 行カスタムビュー（通知とレビュー依頼の両方で再利用、ドット色で区別） |
| `Models.swift` | データモデル・enum 定義（`GitHubNotification`, `UnreviewedPR`, `AssignedItem` 等） |

---

## プロジェクト構成

```
gitkun/
├── CLAUDE.md
├── README.md
├── Makefile
├── gitkun.xcodeproj/
└── gitkun/
    ├── Info.plist            # LSUIElement=YES
    ├── Assets.xcassets/
    │   ├── AppIcon.appiconset/                     # アプリアイコン
    │   ├── MenuBarIcon.imageset/                   # 通常アイコン（template）
    │   ├── MenuBarIconUnread.imageset/             # 未読ありアイコン（original）
    │   ├── MenuBarIconUnreview.imageset/           # 未レビューありアイコン（original）
    │   └── MenuBarIconUnreadAndUnreview.imageset/  # 両方ありアイコン（original）
    └── *.swift
```

---

## 既知の制約・注意事項

- `MenuBarExtra` のラベルは静的レンダリングのため動的更新不可 → `NSStatusItem` を直接管理
- GUI アプリから `gh` を起動すると Keychain アクセスが不安定になるため、`gh auth token` でトークンをキャッシュして `GH_TOKEN` 環境変数で渡す
- Dropbox 経由のアイコンファイルに拡張属性が付くため、`make release` 前に `xattr -cr` を実行
- `make run` は既存プロセスを `pkill` してから起動する（二重起動防止との競合回避）
- `NSMenuItem` のカスタムビューはホバーハイライトを自前実装する必要がある（`NSTrackingArea` + `mouseEntered/mouseExited`）
- `NSMenuItem` のカスタムビューはクリックで `enclosingMenuItem?.menu?.cancelTracking()` を呼ばないとメニューが閉じない

---

## 禁止事項

- OAuth 実装
- DB 導入
- 過剰な UI
- 不要な抽象化

---

## ゴール

最小構成で GitHub 通知とレビュー依頼を見逃さない体験を提供すること。
