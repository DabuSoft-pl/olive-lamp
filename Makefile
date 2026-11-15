DERIVED := build
APP := "$(DERIVED)/Build/Products/Debug/Olive Lamp.app"

.PHONY: generate build test test-live run release screenshots clean

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project OliveLamp.xcodeproj -scheme OliveLamp -configuration Debug -derivedDataPath $(DERIVED) -quiet build

test:
	cd Packages/LampKit && swift test

# Also against the web Lamp's mock server: `node dev/server.mjs` in olivetin-lamp first.
test-live:
	cd Packages/LampKit && LAMP_MOCK_URL=$${LAMP_MOCK_URL:-http://127.0.0.1:8080} swift test

run: build
	open $(APP)

clean:
	rm -rf $(DERIVED) Lamp.xcodeproj OliveLamp.xcodeproj Packages/LampKit/.build

# Developer ID signed, notarized DMG with the Sparkle feed and deltas in build/release (scripts/release.sh lists every
# variable). The team and the notarytool profile default to Dabusoft's own; override them on the command line.
TEAM_ID ?= ZFG7SZ938C
NOTARY_PROFILE ?= dabusoft
release:
	TEAM_ID="$(TEAM_ID)" NOTARY_PROFILE="$(NOTARY_PROFILE)" scripts/release.sh

# The README images, rendered from made-up data (Lamp/App/Screenshots.swift).
screenshots: build
	$(APP)/Contents/MacOS/"Olive Lamp" -AppleLanguages "(en)" -screenshots "$(CURDIR)/docs/images"
