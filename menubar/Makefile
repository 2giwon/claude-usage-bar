.PHONY: check build icon app zip install login unlogin uninstall clean

PRODUCT = ClaudeUsageBar
APP = Claude Usage Bar.app
INSTALL_DIR = $(HOME)/Applications
AGENT = $(HOME)/Library/LaunchAgents/io.github.2giwon.claudeusagebar.plist
# Intel 맥과 Apple 실리콘 맥에서 모두 도는 앱으로 빌드한다
ARCHS = --arch arm64 --arch x86_64
# 배포 zip 과 앱 정보에 들어가는 버전. 배포 때는 make zip VERSION=0.2.0 처럼 넘긴다
VERSION ?= 0.1.0

# 계산 함수 검사 (Xcode 없이 쓰는 테스트 대용)
check:
	swift run UsageBarChecks

build:
	swift build -c release --product $(PRODUCT) $(ARCHS)

# 앱 아이콘(AppIcon.icns)을 다시 만든다. 그림을 바꿨을 때만 돌리고, 결과 파일은 저장소에 넣는다
icon:
	rm -rf AppIcon.iconset
	swift run $(PRODUCT) --icon AppIcon.iconset
	iconutil -c icns AppIcon.iconset -o AppIcon.icns
	rm -rf AppIcon.iconset

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c release --product $(PRODUCT) $(ARCHS) --show-bin-path)/$(PRODUCT)" "$(APP)/Contents/MacOS/$(PRODUCT)"
	cp Info.plist "$(APP)/Contents/Info.plist"
	cp AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" -c "Set :CFBundleVersion $(VERSION)" "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"
	@echo "Built $(APP) $(VERSION)"

# GitHub Releases 에 올릴 zip 을 만든다
zip: app
	rm -f $(PRODUCT)-$(VERSION).zip
	ditto -c -k --keepParent "$(APP)" "$(PRODUCT)-$(VERSION).zip"
	@echo "Made $(PRODUCT)-$(VERSION).zip"

# ~/Applications 에 설치하고 실행한다
install: app
	mkdir -p "$(INSTALL_DIR)"
	pkill -x $(PRODUCT) || true
	rm -rf "$(INSTALL_DIR)/$(APP)"
	cp -R "$(APP)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP)"
	@echo "Installed to $(INSTALL_DIR)/$(APP)"

# 로그인할 때 자동으로 켜지게 한다 (LaunchAgent)
login:
	mkdir -p "$(HOME)/Library/LaunchAgents"
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '<key>Label</key><string>io.github.2giwon.claudeusagebar</string>' \
	  '<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>$(INSTALL_DIR)/$(APP)</string></array>' \
	  '<key>RunAtLoad</key><true/>' \
	  '</dict></plist>' > "$(AGENT)"
	@echo "Will start at login: $(AGENT)"

unlogin:
	rm -f "$(AGENT)"

uninstall: unlogin
	pkill -x $(PRODUCT) || true
	rm -rf "$(INSTALL_DIR)/$(APP)"

clean:
	rm -rf .build "$(APP)" $(PRODUCT)-*.zip AppIcon.iconset
