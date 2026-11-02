.PHONY: project build release run run-release preview snapshot-tool test clean

DERIVED = build
DEST = 'platform=macOS,arch=arm64'

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project SpaceWallpaper.xcodeproj -scheme SpaceWallpaper -configuration Debug -destination $(DEST) -derivedDataPath $(DERIVED) -quiet build

release: project
	xcodebuild -project SpaceWallpaper.xcodeproj -scheme SpaceWallpaper -configuration Release -destination $(DEST) -derivedDataPath $(DERIVED) -quiet build

run: build
	open $(DERIVED)/Build/Products/Debug/SpaceWallpaper.app

run-release: release
	open $(DERIVED)/Build/Products/Release/SpaceWallpaper.app

SEED ?= 1
JOURNEY_SECONDS ?= 0
preview: build
	open -n $(DERIVED)/Build/Products/Debug/SpaceWallpaper.app --args --preview --seed $(SEED) --seconds $(JOURNEY_SECONDS)

snapshot-tool: release
	xcrun swiftc -O -parse-as-library -I $(DERIVED)/Build/Products/Release tools/Snapshot.swift $(filter-out App/AppDelegate.swift App/WallpaperWindow.swift,$(shell find App -name '*.swift')) $(DERIVED)/Build/Products/Release/SpaceCore.o -o $(DERIVED)/snapshot

test:
	cd Packages/SpaceCore && swift test --quiet

clean:
	rm -rf $(DERIVED) SpaceWallpaper.xcodeproj Packages/SpaceCore/.build
