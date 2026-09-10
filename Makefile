.PHONY: build test install install-cli uninstall

build:
	swift build

test:
	swift test

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

install-cli:
	./scripts/install.sh --cli-only
