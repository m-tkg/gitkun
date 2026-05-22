# gitkun

macOS のメニューバーに常駐し、GitHub の未読通知を定期的にチェックする軽量アプリ。

- 未読通知があるとアイコンが切り替わる
- 新規未読が増えると macOS 通知バナー + サウンドで通知
- 通知クリックでブラウザが開く

## 前提条件

- macOS 13 Ventura 以降
- [Xcode](https://developer.apple.com/xcode/)
- [gh CLI](https://cli.github.com/)

```bash
brew install gh
gh auth login
```

## ビルド

```bash
make run     # Debug ビルド & 起動
make debug   # Debug ビルドのみ
make release # Release ビルド
make clean   # ビルド成果物削除
```

## インストール

1. `make release` で `.build/Build/Products/Release/gitkun.app` をビルド
2. `gitkun.app` を `/Applications` へコピー
3. 初回起動時に通知の許可ダイアログが表示されたら「許可」を選択

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
