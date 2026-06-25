# コード署名と公証（Developer ID + notarization）

## なぜ必要か

gitkun はアップデートで `.app` を入れ替える。**ビルドごとに署名が変わると macOS の
自動化(TCC)権限が無効化**されるため、ad-hoc 署名のままだと更新のたびに
「gitkun が Safari / Google Chrome を制御することを許可」を取り直す必要がある。

さらに ad-hoc 署名は **Gatekeeper に弾かれる**ため、ダウンロード（quarantine 付き）した
別 Mac では許可ダイアログすら出ず、既存タブへの移動機能が常にフォールバック（新規タブ）に
なる。

これを防ぐには、ビルドをまたいで**同一の安定した署名**で署名する。Apple Developer Program の
**Developer ID Application** 証明書で署名し、さらに **notarization（公証）** すると、
権限が保持されるうえ Gatekeeper の警告も出なくなり、**他人にも配布可能**になる。

リリースは CI（GitHub Actions）が行うため、CI に証明書と公証情報を **Secrets** として渡す。
Secrets 未設定時は ad-hoc 署名（公証なし）にフォールバックする。

> snapperkun / Whisperkun と同じ Apple Developer アカウント・証明書を使うなら、
> それらのリポジトリに登録済みの **6 つの Secret 値をそのまま gitkun リポジトリにも登録**すれば
> よい（証明書の新規発行は不要）。

---

## 全体の流れ（チェックリスト）

1. [ ] Apple Developer Program に登録済み（年 $99）
2. [ ] 「Developer ID Application」証明書を作成済み（Mac のキーチェーンにある）
3. [ ] その証明書を **`.p12` ファイルに書き出す**
4. [ ] 署名アイデンティティ名・App 用パスワード・Team ID を確認
5. [ ] GitHub に 6 つの Secrets を登録（gitkun リポジトリ）
6. [ ] バージョンを上げてこのブランチを `main` にマージ → CI が署名・公証してリリース
7. [ ] 移行の初回のみ、古い自動化権限を削除して再許可

---

## p12 ファイルとは？

**`.p12`（PKCS#12）は「証明書 + 秘密鍵」を 1 つにまとめた持ち運び用ファイル**。
キーチェーンにある Developer ID 証明書を書き出して作る。CI のクリーンな Mac には自分の
キーチェーンが無いため、この `.p12` を Secrets として渡し、CI 側で取り込んで署名に使う。

> ⚠️ `.p12` は秘密鍵を含む。リポジトリにコミットせず、GitHub Secrets にのみ登録すること。

---

## 手順

### 1〜3. 証明書を `.p12` に書き出す

（snapperkun / Whisperkun で作成済みなら、その `.p12` を流用できる）

1. Xcode > Settings > Accounts に Apple ID を追加し、対象チームで **Manage Certificates…**
2. 左下 `+` > **Developer ID Application** を作成（無ければ）
3. **キーチェーンアクセス**.app >「ログイン」>「自分の証明書」で
   `Developer ID Application: あなたの名前 (チームID)` を選び、右クリック > **書き出す** >
   フォーマット **個人情報交換 (.p12)** で保存。書き出しパスワードを設定
   → このパスワードが `SIGNING_CERTIFICATE_PASSWORD`

### 4. 署名名・App 用パスワード・Team ID を確認

- **署名アイデンティティ名**（`SIGNING_IDENTITY`）:
  ```sh
  security find-identity -v -p codesigning
  ```
  `Developer ID Application: Your Name (TEAMID1234)` の形の文字列。
- **Team ID**（`NOTARY_TEAM_ID`）— 上記カッコ内の 10 桁。
- **App 用パスワード**（`NOTARY_PASSWORD`）— https://appleid.apple.com >
  サインインとセキュリティ > **App 用パスワード** で生成（`xxxx-xxxx-xxxx-xxxx`）。

### 5. GitHub Secrets を登録（gitkun リポジトリ）

**Settings > Secrets and variables > Actions > New repository secret** で 6 つ登録:

| Secret 名 | 値 |
|---|---|
| `SIGNING_CERTIFICATE_P12_BASE64` | `.p12` を base64 化した文字列 |
| `SIGNING_CERTIFICATE_PASSWORD` | `.p12` 書き出し時のパスワード |
| `SIGNING_IDENTITY` | `Developer ID Application: Your Name (TEAMID1234)` |
| `NOTARY_APPLE_ID` | Apple ID（メールアドレス） |
| `NOTARY_PASSWORD` | App 用パスワード |
| `NOTARY_TEAM_ID` | Team ID（10桁） |

base64 化（`.p12` を 1 行のテキストにしてコピー）:
```sh
base64 -i DeveloperID.p12 | pbcopy
```

> `gh` CLI でまとめて登録する例:
> ```sh
> gh secret set SIGNING_CERTIFICATE_P12_BASE64 --repo m-tkg/gitkun < <(base64 -i DeveloperID.p12)
> gh secret set SIGNING_CERTIFICATE_PASSWORD   --repo m-tkg/gitkun
> gh secret set SIGNING_IDENTITY               --repo m-tkg/gitkun
> gh secret set NOTARY_APPLE_ID                --repo m-tkg/gitkun
> gh secret set NOTARY_PASSWORD                --repo m-tkg/gitkun
> gh secret set NOTARY_TEAM_ID                 --repo m-tkg/gitkun
> ```

### 6. バージョンを上げてマージ

`project.pbxproj` の `MARKETING_VERSION` を上げて `main` にマージすると、リリース
ワークフローが **Developer ID 署名 → 公証 → staple** して `v<version>` を作成する。

- `SIGNING_*` のみで `NOTARY_*` が無い → 署名のみ（公証スキップ＝Gatekeeper 警告は残る）
- どちらも無い → ad-hoc 署名（権限は保持されない）

### 7. 移行時の一回だけの再許可

ad-hoc 版（〜v1.10.0）から署名版へ切り替わる初回だけ署名が変わるため:

1. システム設定 > プライバシーとセキュリティ > 自動化 で古い gitkun のエントリを削除
   （無ければスキップ）。ターミナルなら `tccutil reset AppleEvents com.mtkg.gitkun`
2. 新しい版を起動し、PR をクリックして再度「Safari / Google Chrome を制御」を許可

以降、同じ証明書で署名されたアップデートでは権限が保持される。

---

## ローカルで署名する場合（任意・開発用）

`make release` でビルドした後、手元で Developer ID 署名・公証する:

```sh
APP=.build/Build/Products/Release/gitkun.app
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID1234)" "$APP"
ditto -c -k --keepParent "$APP" notarize.zip
xcrun notarytool submit notarize.zip --apple-id "<apple-id>" --password "<app-pw>" --team-id "<team-id>" --wait
xcrun stapler staple "$APP"
```
