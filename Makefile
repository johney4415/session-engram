.PHONY: build test install uninstall

build:
	swift build

test:
	swift test

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh
