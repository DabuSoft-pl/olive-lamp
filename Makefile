DERIVED := build
APP := "$(DERIVED)/Build/Products/Debug/Olive Lamp.app"

.PHONY: generate build test test-live run release clean

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

# Developer ID signed, notarized DMG with the Sparkle feed and deltas in build/release; scripts/release.sh lists what
# it needs (TEAM_ID=ZFG7SZ938C NOTARY_PROFILE=tendbar make release).
release:
	scripts/release.sh
