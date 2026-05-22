APP_NAME  = gitkun
SCHEME    = $(APP_NAME)
PROJECT   = $(APP_NAME).xcodeproj
BUILD_DIR = .build
RELEASE   = $(BUILD_DIR)/Build/Products/Release
DEBUG     = $(BUILD_DIR)/Build/Products/Debug

.PHONY: build release debug run clean

## Debug ビルド（デフォルト）
build: debug

## Debug ビルド
debug:
	xcodebuild -project $(PROJECT) \
	           -scheme $(SCHEME) \
	           -configuration Debug \
	           -derivedDataPath $(BUILD_DIR) \
	           build

## Release ビルド
release:
	@xattr -cr $(APP_NAME)/Assets.xcassets 2>/dev/null || true
	@rm -rf $(RELEASE)/$(APP_NAME).app
	xcodebuild -project $(PROJECT) \
	           -scheme $(SCHEME) \
	           -configuration Release \
	           -derivedDataPath $(BUILD_DIR) \
	           build

## Debug ビルドして起動（既存プロセスを終了してから起動）
run: debug
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	open $(DEBUG)/$(APP_NAME).app

## ビルド成果物を削除
clean:
	rm -rf $(BUILD_DIR)
