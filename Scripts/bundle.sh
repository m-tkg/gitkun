#!/usr/bin/env bash
# ビルド成果物を .app バンドルにまとめる。
# 使い方: bash Scripts/bundle.sh [debug|release]   (既定: release)
#
# ローカル検証用ビルド: LOCAL=1 bash Scripts/bundle.sh debug
#   本番アプリ(com.mtkg.gitkun)と TCC 権限（Apple Events / ブラウザ制御）が衝突しないよう、
#   バンドルID と表示名を分けた「gitkun (Local)」を生成する。これによりシステム設定の
#   権限一覧に本番と別エントリとして並び、独立して許可できる。
#   再ビルドで権限が外れるのを避けたい場合は、安定した自己署名IDを併用する:
#     SIGN_IDENTITY="Apple Development: ..." LOCAL=1 bash Scripts/bundle.sh debug
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
LOCAL="${LOCAL:-0}"

# ローカル検証ビルド（LOCAL=1）はバンドルID/表示名を分けて本番と権限(TCC)を分離する。
# CFBundleExecutable は Info.plist の "gitkun" 固定（バイナリ名と一致させる）。
if [[ "$LOCAL" == "1" ]]; then
  APP_NAME="gitkun (Local)"
  BUNDLE_ID="com.mtkg.gitkun.local"
else
  APP_NAME="gitkun"
  BUNDLE_ID="com.mtkg.gitkun"
fi
APP="$ROOT/$APP_NAME.app"

echo "==> Building ($CONFIG)"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
swift build -c "$CONFIG" --package-path "$ROOT"

echo "==> Bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_DIR/gitkun" "$APP/Contents/MacOS/gitkun"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# ローカル検証ビルドはバンドルID/表示名を差し替える（CFBundleExecutable は gitkun のまま）。
if [[ "$LOCAL" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
fi

# メニューバー用アイコン（実行時に Bundle.main から読み込む）。
# 未読/未レビューの4状態 + kuntraykun 一覧用（MenuBarIcon.png）を同梱する。
for icon in MenuBarIcon MenuBarIconUnread MenuBarIconUnreview MenuBarIconUnreadAndUnreview; do
  if [[ -f "$ROOT/Resources/$icon.png" ]]; then
    cp "$ROOT/Resources/$icon.png" "$APP/Contents/Resources/$icon.png"
  fi
done

# アプリアイコン: Resources/AppIcon.png から .icns を生成する。
ICON_SRC="$ROOT/Resources/AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
  echo "==> Generating app icon"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

# コード署名。
# Resources/gitkun.entitlements の apple-events エンタイトルメントはどちらの署名でも必須。
# これが無いと Hardened Runtime 下で Safari / Chrome へ Apple Event を送れず、TCC ダイアログも
# 出ずに -1743 で静かに失敗する。entitlements はコメントを入れると AMFI のパーサが拒否するため、
# キーのみのミニマル構成にしてある（説明はここに集約）。
# SIGN_IDENTITY が指定されていれば、その安定した署名アイデンティティで署名する。
# 安定署名にすると、アップデートで .app を入れ替えても TCC 権限（ブラウザ制御）が保持される
# （アドホック署名はビルドごとに署名が変わり、権限が無効化されてしまう）。
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
ENTITLEMENTS="$ROOT/Resources/gitkun.entitlements"
if [[ -n "$SIGN_IDENTITY" ]]; then
  # Developer ID 署名 + Hardened Runtime + セキュアタイムスタンプ（notarization の要件）。
  echo "==> Codesign ($SIGN_IDENTITY)"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP"
else
  # ad-hoc 署名（Hardened Runtime + apple-events エンタイトルメント）。
  echo "==> Codesign (ad-hoc)"
  codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign - "$APP"
fi

echo "==> Done: $APP"
echo "起動: open \"$APP\"   （初回はシステム設定 > プライバシーとセキュリティ > オートメーション で Safari/Chrome 制御を許可）"
