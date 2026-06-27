# gitkun

macOS のメニューバーに常駐し、GitHub の未読通知を定期的にチェックする軽量アプリ。

- 未読通知があるとアイコンが切り替わる
- 新規未読が増えると macOS 通知バナー + サウンドで通知
- 通知クリックでブラウザが開く

## 前提条件

- macOS 13 Ventura 以降
- Swift toolchain（`swift build` / `swift test`。Xcode 本体は不要、Command Line Tools で可）
- [gh CLI](https://cli.github.com/)

```bash
brew install gh
gh auth login
```

## ビルド

Xcode は使わず Swift Package Manager + `Scripts/bundle.sh` でビルドする。

```bash
swift build                       # ビルド（Debug）
swift test                        # ユニットテスト
bash Scripts/bundle.sh release    # .app を組み立て（Release・ad-hoc 署名）

# ローカル検証用（本番と権限を分けた「gitkun (Local)」を生成して起動）
LOCAL=1 bash Scripts/bundle.sh debug && open "gitkun (Local).app"
```

## インストール

1. `bash Scripts/bundle.sh release` で `gitkun.app`（リポジトリ直下）をビルド
2. `gitkun.app` を `/Applications` へコピー
3. 初回起動時に通知の許可ダイアログが表示されたら「許可」を選択

## リリース手順

バージョンは `Resources/Info.plist` の `CFBundleShortVersionString`（3桁 semver、例 `1.2.0`）を唯一の源とする。アプリが表示するバージョンもこの値を参照する。

リリースは GitHub Actions（`.github/workflows/release.yml`）が **main への push または手動実行（Run workflow）をトリガー**に動き、現在の `CFBundleShortVersionString` を読み取って `v<version>` のリリースがまだ無ければ、`bundle.sh` でビルド → `gitkun.app` を zip 化 → タグ作成 → GitHub Releases へバイナリ添付までを自動で行う。

```
1. PR で CFBundleShortVersionString を上げる（例 1.2.0）
2. main にマージ → 自動で v1.2.0 がタグ付けされ、gitkun.zip 付きで公開される
```

- バージョン未変更の main push は「既存リリースあり」としてスキップされる（安全）
- 手動で出したいときは Actions の **Release → Run workflow**
- タグは CI が自動作成するため、手で `git tag` / `gh release create` する必要はない

## 使い方

起動するとメニューバーにアイコンが表示される。

| アイコン | 状態 |
|---|---|
| 通常アイコン | 未読なし |
| 通知アイコン | 未読あり |

クリックするとメニューが開く。

```
GitHub Notifications
────────────────────
● owner/repo
  PR タイトル
  5m ago
────────────────────
Status ▶
  Status: OK
  Unread: 1
  Last checked: 23:45
────────────────────
Refresh
Launch at login: OFF
────────────────────
Quit
```

- **通知行クリック** — ブラウザで該当ページを開き、リストから削除
- **Status** — サブメニューで詳細ステータスを確認
- **Refresh** — 手動で即時更新（フェッチ中は無効）
- **Launch at login** — ログイン時の自動起動を ON/OFF

## アーキテクチャ

```
gitkunApp.swift               @main、二重起動防止
AppDelegate.swift             NSStatusItem 管理、NSMenu 構築、アイコン切り替え
├── AppState.swift            状態管理・差分判定・通知発火
├── GitHubNotificationService.swift  gh CLI 実行（actor、トークンキャッシュ）
├── NotificationPoller.swift  タイマーポーリング
├── LocalStore.swift          UserDefaults ラッパー
├── UserNotifier.swift        UNUserNotificationCenter
├── LaunchAtLoginManager.swift  SMAppService
├── URLResolver.swift         API URL → Web URL 変換
└── NotificationMenuItemView.swift  通知行カスタムビュー（AppKit）
```

## ログ確認

エラー時は Console.app で詳細ログを確認できる。

```
subsystem == "com.mtkg.gitkun"
```

またはメニューの Status サブメニューから「Open Console.app」で起動し、「Copy Error」でエラー詳細をクリップボードにコピー可能。
