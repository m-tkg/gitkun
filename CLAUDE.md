# CLAUDE.md

## プロジェクト概要

gitkun は、macOS のメニューバーに常駐し、GitHub の未読通知と「レビュアーとして自分に review request が来ている未マージ PR」を定期的にチェックして、新規分をユーザーに知らせる軽量なユーティリティアプリである。加えて、自分が assignee または author の open PR（My PRs）と、自分にアサインされている open Issue の一覧をメニューから参照できる。

個人利用を前提とした MVP とし、シンプルで安定した動作を最優先とする。

---

## 前提条件

- macOS 13 Ventura 以降
- Swift toolchain がインストール済みであること（`swift build` / `swift test` が使えること。Xcode 本体は不要だが Command Line Tools は必要）
- `gh` CLI がインストール済みであること（`/opt/homebrew/bin/gh` または `/usr/local/bin/gh`）
- `gh auth login` が完了していること
- App Store 配布や sandbox 制約は考慮しない

---

## 技術スタック

- Swift Package Manager（swift-tools-version 5.9、Xcode/xcodeproj は使わない）
- AppKit（NSStatusItem、NSMenu、NSPopover、アイコン切り替え、音声再生、ブラウザ起動）
- SwiftUI（gitkunApp.swift の Settings シーン・SettingsView のみ）
- async/await + Combine
- OSLog（ロギング）

対応OSは macOS 13+ のみ。後方互換性は考慮しない。

ビルドは whisperkun / snapperkun と同様、SwiftPM + `Scripts/bundle.sh`（.app を手組み）で行う。
`.app` バンドルは bundle.sh が `swift build` の成果物・`Resources/` のアイコン・`Info.plist` から組み立てる。

---

## ビルド・実行

Makefile は廃止。`swift` コマンドと `Scripts/bundle.sh` を直接使う。

```bash
# ビルド（Debug）
swift build

# ユニットテスト（gitkunCoreTests）
swift test

# .app を組み立て（Release・ad-hoc 署名）
bash Scripts/bundle.sh release

# ローカル検証用 .app（本番と TCC 権限を分離した「gitkun (Local)」を生成して起動）
pkill -x gitkun 2>/dev/null; LOCAL=1 bash Scripts/bundle.sh debug && open "gitkun (Local).app"

# ビルド成果物削除
swift package clean; rm -rf .build "gitkun.app" "gitkun (Local).app"
```

`bash Scripts/bundle.sh release` はローカル向けの **ad-hoc 署名**ビルド。配布用の署名・公証は CI が行う（後述）。
`LOCAL=1` を付けると bundle ID を `com.mtkg.gitkun.local` に分け、本番アプリと
オートメーション(TCC)権限が衝突しないようにする。`SIGN_IDENTITY="Apple Development: …"` を併用すると
ローカルでも安定署名になり、再ビルドのたびに権限を取り直さずに済む。

---

## ブランチ運用（必須）

- **`main` ブランチへ直接コミット / push しない。** 変更は必ず Pull Request 経由で行う。
- 作業ブランチは**必ずその時点の最新の `main` から切る**
  （`git fetch origin && git switch main && git pull --ff-only` してから分岐）。
- PR は `gh pr create` で作成し、マージはレビュー後に行う（GitHub 操作は `gh` を使う）。
- **PR 作成後に追加修正するときは、まずその PR がマージ済みでないか確認する**
  （`gh pr view <番号> --json state,mergedAt`）。マージ済みのブランチへ push しても `main` には
  反映されない（孤立コミットになる）。マージ済みなら**最新 `main` から新ブランチを切り直し**、
  必要なら `Resources/Info.plist` の `CFBundleShortVersionString` を上げて別 PR を出す。
- リリース用 Actions は `push: branches: [main]` で発火するため、**main への push がそのまま
  リリースに直結する**。事故防止の意味でも main 直 push は避け、PR マージ経由にする。

---

## リリース・署名・配布

リリースは GitHub Actions（`.github/workflows/release.yml`）が担当する。

- `main` に push されると、`Resources/Info.plist` の `CFBundleShortVersionString` を読み取り、
  `v<version>` タグのリリースを自動作成する（同名リリースが既にあればスキップ）。
  → **リリースは `CFBundleShortVersionString` を上げて `main` にマージするだけ**。
- ビルド成果物（`gitkun.app` を zip 化）をリリースアセットとして添付。自己更新はこの zip を取得する。

### 署名・公証（Developer ID + notarization）

- 配布版は **Developer ID Application 証明書**（Team ID `G72M73C546`）で署名し、**公証（notarization）+ staple** する。
  `Scripts/bundle.sh` が `SIGN_IDENTITY` 環境変数で Developer ID 署名まで行う（CI は証明書を一時キーチェーンに
  import してから `SIGN_IDENTITY` を渡す）。`SIGN_IDENTITY` 未設定なら ad-hoc 署名にフォールバックする。
  bundle.sh は ad-hoc / Developer ID どちらの分岐でも
  `codesign --options runtime --timestamp --entitlements Resources/gitkun.entitlements` 相当を実行する
  （`--entitlements` を渡さないと apple-events entitlement が剥がれるため必須。
  CI には剥がれを検知する `Verify signing and entitlements` ステップもある）。
- **安定署名でなければアップデート越しに自動化(TCC)権限が保持されない**。ad-hoc はビルドごとに署名が
  変わり、更新のたびにブラウザ制御の許可を取り直す羽目になる。公証すれば Gatekeeper 警告も消え、他人にも配布可能。
- 署名・公証情報は GitHub の **Secrets 6 つ**で CI に渡す。**Secrets 未設定時は ad-hoc 署名（公証スキップ）に
  フォールバック**する。

  | 用途 | Secret |
  |---|---|
  | 署名 | `SIGNING_IDENTITY` / `SIGNING_CERTIFICATE_PASSWORD` / `SIGNING_CERTIFICATE_P12_BASE64` |
  | 公証 | `NOTARY_APPLE_ID` / `NOTARY_PASSWORD` / `NOTARY_TEAM_ID` |

  snapperkun / whisperkun 等と同じ Apple Developer アカウントなら、それらに登録済みの 6 値をそのまま流用できる
  （証明書の新規発行は不要）。登録手順・移行時の権限再許可の詳細は **`docs/SIGNING.md`** を参照。

---

## 機能要件

### 基本機能

- メニューバーに常駐するアプリ
- 二重起動防止（同じ Bundle ID が起動中なら即終了）
- macOS 起動時に自動起動可能（Launch at login）
- GitHub の未読通知・未レビュー PR・自分の PR（assignee + author マージ）・自分アサインの Issue を定期取得（4 本並行フェッチ）
- 新規未読 / 新規レビュー依頼があれば macOS 通知バナー + 音（My PRs / Assigned Issues は通知しない）
- メニューから通知一覧、レビュー依頼一覧、My PRs / Assigned Issues 一覧を表示
- 項目クリックでブラウザ遷移（クリックで一覧から即削除はしない）。通知だけはクリック時に refresh を実行し、GitHub 側で既読になった通知が次フェッチで一覧から消える。レビュー依頼 / My PRs / Assigned Issues は次ポーリングの再取得で更新
- **未読/未レビューの組み合わせに応じてメニューバーアイコンが4通りに切り替わる**（My PRs / Assigned Issues はアイコン状態に影響しない）
- 約1時間ごとに自リポジトリ（`m-tkg/gitkun`）の最新リリースを確認し、新バージョンがあれば通知 + メニューから自己更新できる（後述「更新チェック・自己更新」）

### 未レビュー PR の WIP フィルタ

以下の PR は review 待ちと判定せず、Review Requests に表示しない（`UnreviewedPR.isReviewWaiting`）:

- draft PR
- タイトルが `[WIP]` で始まる（大文字小文字は区別しない）
- `wip` ラベルが付いている（大文字小文字は区別しない）

このフィルタは設定（`excludeWIP`、デフォルト ON）で OFF にできる。適用は `AppState` 側で行い、
`GitHubNotificationService` はフィルタしない生の検索結果を返す。OFF→ON/ON→OFF の切り替えは
次のポーリングまたは Refresh で反映される（OFF にすると WIP の PR が新規として通知され得る）。

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
- 起動時に即フェッチ（`Poller.start()` が即時1回発火）
- 1ポーリングで通知・レビュー依頼・assignee:@me・author:@me を `async let` で並行フェッチ（4 本）
- ポーリング制御: `isFetching` フラグで同時実行を防止
- 一部の API が失敗しても、成功した分の結果は反映する（エラー詳細は `lastErrorDetail` に連結）
- My PRs は assignee / author の少なくとも片方が成功した場合に更新（両方失敗時は前回値を据え置き）、Assigned Issues は assignee 側成功時のみ更新

---

## 新規判定

差分判定と My PRs マージの純粋ロジックは `FetchDiff.swift` に分離されており、ユニットテストの対象。

### 通知

- `id` の差分で判定（`FetchDiff.newItems`。フェッチ結果から消えた ID は既知集合に残らない）

### 未レビュー PR

- 同じく `id` の差分で判定（`UnreviewedPR.id` は `Int`、キャッシュも `Set<Int>` で統一）

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
  - `AppDelegate` が `appState.$notifications` / `appState.$unreviewedPRs` の `isEmpty` を `combineLatest` で監視し、`NSStatusItem.button?.image` を直接差し替え（未読/未レビューの有無はリストから導出。専用フラグは持たない）
  - `MenuBarExtra` は使用しない（ラベルが静的レンダリングのため動的更新不可）

| 未読 | 未レビュー | 使用アセット |
|---|---|---|
| × | × | `MenuBarIcon` |
| ○ | × | `MenuBarIconUnread` |
| × | ○ | `MenuBarIconUnreview` |
| ○ | ○ | `MenuBarIconUnreadAndUnreview` |

### アイコンアセット

Asset Catalog（`.xcassets`）は使わない。PNG を `Resources/` に直置きし、bundle.sh が `.app` の
`Contents/Resources/` へコピーする。アプリは `Bundle.main.url(forResource:withExtension:)` で読み込む。

- `Resources/AppIcon.png` — アプリアイコン元画像（1024px）。bundle.sh が `sips`+`iconutil` で `AppIcon.icns` を生成
- `Resources/MenuBarIcon.png` — 通常アイコン（32px）。`AppDelegate.menuBarImage(named:)` が `isTemplate = true` を設定しライト/ダークに追従。kuntraykun 一覧表示にもこのファイルが使われる
- `Resources/MenuBarIconUnread.png` — 未読ありアイコン（32px、色付き = original）
- `Resources/MenuBarIconUnreview.png` — 未レビューありアイコン（32px、色付き）
- `Resources/MenuBarIconUnreadAndUnreview.png` — 両方ありアイコン（32px、色付き）

メニューバーアイコンは `NSImage(named:)` ではなく `AppDelegate.menuBarImage(named:)` が
Bundle からファイルを読み、`isTemplate`（通常アイコンのみ true）と `size`（16pt）をコードで設定する。

---

## 通知仕様

### トリガー

- 新規未読が1件以上増えた場合（初回フェッチを除く）
- 新規レビュー依頼が1件以上増えた場合（初回フェッチを除く）

### 内容

- 通知: タイトル `"GitHub Notifications"`、本文 `"PR title (+N more)"`、音は `unreadSoundName`
- レビュー依頼: タイトル `"GitHub Review Requests"`、本文 `"PR title (+N more)"`、音は `reviewSoundName`
- アプリ更新通知の音は `updateSoundName`
- いずれも音名が `N/A` の場合は鳴らさない（バナーは出る）

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

## 更新チェック・自己更新

- 起動時に1回、以降は約1時間ごとに `gh api /repos/m-tkg/gitkun/releases/latest` で最新リリースを確認（`Poller` の第2インスタンス）。手動 Refresh 時にも確認する
- `VersionComparator` がタグ（`v` プレフィックス可）と `CFBundleShortVersionString` を数値比較し、新しければ `AppState.availableUpdate` にセット
- 新バージョンを初めて検知したときだけ通知バナー + 音（`lastNotifiedReleaseTag` で再通知を抑止）
- メニューに `⬆ Update to vX.Y.Z…` 項目が出現。実行すると `SelfUpdater` が:
  1. `gh release download` で zip を取得
  2. `ditto` で展開し、Bundle ID を検証
  3. 旧プロセス終了を待って `.app` を入れ替える切り離しシェルスクリプトを起動し、自身は終了
- 更新チェックの失敗はログのみで `status` には影響させない

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
  Version: X.Y.Z
  Unread: X
  Review requests: Y
  My PRs: N
  Assigned issues: M
  Last checked: HH:mm
  [エラー詳細]            ← エラー時のみ
  [Copy Error]            ← エラー時のみ
  [Open Console.app]      ← エラー時のみ
────────────────────
⬆ Update to vX.Y.Z…      ← 新バージョン検知時のみ表示
────────────────────
Refresh                   ← フェッチ中は disabled
Settings…                 ← 設定ウィンドウを開く（⌘,）
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
| `unreadSoundName` | String | `"Glass"` |
| `reviewSoundName` | String | `"Glass"` |
| `updateSoundName` | String | `"Glass"` |
| `excludeWIP` | Bool | `true` |
| `knownNotificationIDs` | [String] | `[]` |
| `knownUnreviewedPRIDs` | [Int] | `[]` |
| `lastNotifiedReleaseTag` | String? | `nil` |

通知音と Launch at login はメニューの `Settings…` から変更できる（`SettingsView.swift` を
`AppDelegate` が `NSWindow` + `NSHostingController` で表示。SwiftUI の Settings シーンは
macOS 14+ でセレクタ経由の表示がブロックされたため使わない）。
未読 / レビュー依頼 / 更新検知でそれぞれ別の音を設定でき、選択肢は `/System/Library/Sounds`
から実行時に列挙、選択時にプレビュー再生する。各 Picker の先頭には `N/A`
（`SystemSounds.noSound`）があり、選ぶとそのイベントの音だけ鳴らさない。
`@AppStorage` と `LocalStore` は同じ UserDefaults キーを共有する。
ポーリング間隔のみ UI 未実装で `LocalStore` 経由で変更可能。
旧キー `diffStrategy` / `knownNotificationUpdatedAts` / `soundEnabled` は廃止済みで、
起動時に削除される（音全体の ON/OFF は各サウンドの N/A 選択に置き換え）。

---

## アーキテクチャ

| ファイル | 役割 |
|---|---|
| `gitkunApp.swift` | `@main`、`NSApplicationDelegateAdaptor`、二重起動防止 |
| `AppDelegate.swift` | `NSStatusItem` 管理、`NSMenu` 構築、アイコン切り替え（Combine） |
| `AppState.swift` | `@MainActor ObservableObject`、状態管理、フェッチのオーケストレーション、通知発火（差分判定・マージは `FetchDiff` に委譲） |
| `FetchDiff.swift` | 差分判定・My PRs マージの純関数（テスト対象） |
| `GitHubNotificationService.swift` | `actor`、`gh` CLI 実行、トークンキャッシュ、通知・未レビュー PR・assignee 検索・author 検索・リリース取得のフェッチ |
| `ProcessRunner.swift` | 外部コマンド実行の共通ランナー（pipe ストリーム読みで deadlock 回避） |
| `Poller.swift` | `Timer` の closure ベースラッパー（通知ポーリングと更新チェックで2インスタンス使用） |
| `SelfUpdater.swift` | 最新リリース zip の取得・展開・`.app` 入れ替え・再起動 |
| `LocalStore.swift` | `UserDefaults` ラッパー |
| `UserNotifier.swift` | `UNUserNotificationCenter`、通知クリックでブラウザ起動 |
| `LaunchAtLoginManager.swift` | `SMAppService`（macOS 13+） |
| `URLResolver.swift` | API URL → Web URL 変換（通知のみ） |
| `NotificationMenuItemView.swift` | 行カスタムビュー（通知とレビュー依頼の両方で再利用、ドット色で区別） |
| `SettingsView.swift` | 設定の SwiftUI ビュー（通知音 3 種（N/A で個別ミュート）・WIP 除外・Launch at login・現在/最新バージョン表示。AppDelegate が NSWindow で表示）+ システムサウンド列挙 |
| `Models.swift` | データモデル・enum 定義（`GitHubNotification`, `UnreviewedPR`, `AssignedItem`, `ReleaseInfo`, `VersionComparator` 等） |

---

## プロジェクト構成

```
gitkun/
├── CLAUDE.md
├── README.md
├── Package.swift            # SwiftPM（gitkunCore + gitkun + gitkunCoreTests の3ターゲット）
├── Scripts/
│   └── bundle.sh            # swift build → .app 手組み → codesign
├── Resources/              # bundle.sh が .app の Contents/ へコピー
│   ├── Info.plist           # LSUIElement=YES。CFBundleShortVersionString がバージョンの真実
│   ├── gitkun.entitlements  # apple-events のみ（コメント無し: AMFI 制約）
│   ├── AppIcon.png          # 1024px → bundle.sh が AppIcon.icns を生成
│   ├── MenuBarIcon.png                  # 通常アイコン（template、32px）
│   ├── MenuBarIconUnread.png            # 未読あり（色付き、32px）
│   ├── MenuBarIconUnreview.png          # 未レビューあり（色付き、32px）
│   └── MenuBarIconUnreadAndUnreview.png # 両方あり（色付き、32px）
├── Sources/
│   ├── gitkunCore/          # 純粋ロジック（テスト対象、AppKit 非依存）
│   │   ├── Models.swift  URLResolver.swift  FetchDiff.swift  GitHubTabMatcher.swift
│   └── gitkun/             # 実行ファイル本体（AppKit/SwiftUI/Combine 依存）
│       └── *.swift
└── Tests/
    └── gitkunCoreTests/     # ユニットテスト（@testable import gitkunCore。アプリは起動しない）
        └── *Tests.swift
```

### テスト

- テスト対象は `gitkunCore` ターゲットの純粋ロジック（`Models.swift`・`URLResolver.swift`・`FetchDiff.swift`・`GitHubTabMatcher.swift`）。テストは `@testable import gitkunCore` でアクセスする
  - アプリ（`gitkun` ターゲット）を起動しないため、テスト実行時に GitHub ポーリングや通知権限ダイアログが発生しない
  - 新たにテスト対象のロジックを増やす場合は、AppKit 非依存なら `Sources/gitkunCore/` に置く。app から使う型は `public` 化する（テストは `@testable` なので internal でも見える）
- 実行は `swift test`

---

## 既知の制約・注意事項

- `MenuBarExtra` のラベルは静的レンダリングのため動的更新不可 → `NSStatusItem` を直接管理
- GUI アプリから `gh` を起動すると Keychain アクセスが不安定になるため、`gh auth token` でトークンをキャッシュして `GH_TOKEN` 環境変数で渡す
- ローカル起動は `LOCAL=1 bash Scripts/bundle.sh debug` で `pkill -x gitkun` してから `open`（二重起動防止との競合回避）
- `Resources/gitkun.entitlements` にコメントを入れると codesign の AMFI パーサが `syntax error` で失敗するため、キーのみのミニマル構成にする
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

---

## Kuntraykun 連携（実装済み）

本アプリは kuntraykun（`com.mtkg.kuntraykun`）にメニューバーアイコンを集約させる連携に対応している。
- 実装: `Sources/gitkun/AppDelegate.swift` に `KuntraykunBridge` を同梱（whisperkun / snapperkun と同じく
  同ファイル内に置く）。`applicationDidFinishLaunching` で
  `bridge.start()` を配線し、`setHidden` は `statusItem.isVisible`、`popUpMenu` は `statusItem.menu?.popUp` に委譲する。
- 分散通知 `sync`/`showMenu` を観測し、起動時に `appLaunched` を送信。管理対象 かつ kuntraykun 起動中なら
  自分のアイコンを隠し、`showMenu` で自分のメニューを指定座標に `popUp` する（未起動ならフォールバック表示）。
- 仕様: kuntraykun リポジトリ `docs/kun-integration-protocol.md`、共通方針は `../CLAUDE_base.md`「Kuntraykun 連携」。
- 管理対象フラグは `UserDefaults`（キー `KuntraykunManaged`）に永続化する。
- **kuntraykun 一覧用のアイコン**: kuntraykun は各アプリの `Contents/Resources/MenuBarIcon.png` を読んで一覧に表示する。
  SwiftPM 移行で Asset Catalog を廃止し、メニューバーアイコンは `Resources/*.png` を直接バンドルに同梱するように
  なったため、`Resources/MenuBarIcon.png` がそのまま kuntraykun 一覧用にも使われる（専用同梱は不要になった）。
  アプリ本体のアイコン切り替えも同じ PNG 群を `Bundle.main` から読む。
- **実アイコンのライブ書き出し（v2）**: 未読/未レビューで色付きに切り替わる現在のアイコンを kuntraykun 一覧へ反映するため、
  `KuntraykunIconExport.export(_:)`（`Sources/gitkun/KuntraykunIconExport.swift`）で、`statusItem.button?.image` を
  設定する箇所すべて（起動時＋4状態の `combineLatest` sink）で現在アイコンを
  `~/Library/Application Support/Kuntraykun/MenuBarIcons/<基底ID>.png` に書き出す（テンプレートは `.template` マーカー併記）。
  kuntraykun はこれを優先して読むため、gitkun の状態色がそのまま一覧に出る。
