# CCQuick Makefile

.PHONY: build release run clean install uninstall open test

# 测试
test:
	xcodebuild test -scheme CCQuick -configuration Debug -destination 'platform=macOS'

# 构建目录
BUILD_DIR = $(HOME)/Library/Developer/Xcode/DerivedData/CCQuick-*/Build/Products
APP_NAME = CCQuick.app

# Debug 构建
build:
	xcodebuild -scheme CCQuick -configuration Debug build

# Release 构建（优化、无调试符号）
release:
	xcodebuild -scheme CCQuick -configuration Release build

# 运行 Debug 版本
run: build
	@APP_PATH=$$(find $(HOME)/Library/Developer/Xcode/DerivedData -name "$(APP_NAME)" -path "*Debug*" | head -1); \
	if [ -n "$$APP_PATH" ]; then open "$$APP_PATH"; else echo "App not found"; fi

# 运行 Release 版本
run-release: release
	@APP_PATH=$$(find $(HOME)/Library/Developer/Xcode/DerivedData -name "$(APP_NAME)" -path "*Release*" | head -1); \
	if [ -n "$$APP_PATH" ]; then open "$$APP_PATH"; else echo "App not found"; fi

# 打开 Xcode
open:
	open CCQuick.xcodeproj

# 清理构建产物
clean:
	xcodebuild -scheme CCQuick clean
	rm -rf $(HOME)/Library/Developer/Xcode/DerivedData/CCQuick-*

# 安装到 Applications（Release 版本）
install: release
	@APP_PATH=$$(find $(HOME)/Library/Developer/Xcode/DerivedData -name "$(APP_NAME)" -path "*Release*" | head -1); \
	if [ -n "$$APP_PATH" ]; then \
		rm -rf /Applications/$(APP_NAME); \
		cp -R "$$APP_PATH" /Applications/; \
		echo "Installed to /Applications/$(APP_NAME)"; \
	else \
		echo "Release app not found. Run 'make release' first."; \
	fi

# 从 Applications 移除
uninstall:
	rm -rf /Applications/$(APP_NAME)
	echo "Uninstalled"

# 显示帮助
help:
	@echo "CCQuick Build Commands:"
	@echo "  make test         - 运行单元测试"
	@echo "  make build        - Debug 构建"
	@echo "  make release      - Release 构建"
	@echo "  make run          - 构建并运行 Debug 版本"
	@echo "  make run-release  - 构建并运行 Release 版本"
	@echo "  make open         - 打开 Xcode 项目"
	@echo "  make clean        - 清理构建产物"
	@echo "  make install      - 安装 Release 版本到 Applications"
	@echo "  make uninstall    - 从 Applications 移除"