# Makefile for ZigTSC project

ZIGTSC         := ./zig-out/bin/zigtsc
ZIGTSC_RELEASED := $(shell which zigtsc 2>/dev/null || echo $(HOME)/.zigtsc/bin/zigtsc)

# Default target
all: build demo

# Build the zigtsc binary
build:
	zig build

# Clean Zig cache and output
clean:
	rm -rf .zig-cache/ zig-out/ zig-pkg/

# Release: clean build, bump version, commit, tag, push.
# Usage: make release          (auto-bumps minor, e.g. 0.5.0 → 0.6.0)
#        make release V=1.0.0  (explicit version)
release: clean build
	./scripts/release.sh $(V)

# ── demo ──────────────────────────────────────────────────────────────────────

# Run all demo tasks in order (builds first)
demo: build demo-init demo-transpile demo-compile demo-run

demo-init:
	rm -rf /tmp/demo && \
	mkdir -p /tmp/demo && \
	$(ZIGTSC) init /tmp/demo

demo-transpile:
	$(ZIGTSC) transpile /tmp/demo/src/main.ts

demo-compile:
	$(ZIGTSC) compile /tmp/demo/src/zigtscout

demo-run:
	$(ZIGTSC) run /tmp/demo/zig-out/bin/main && \
	$(ZIGTSC) run /tmp/demo/zig-out/wasm/main.wasm

# ── demo-released ─────────────────────────────────────────────────────────────

# Run all demo tasks against the installed (released) binary
demo-released: demo-released-check demo-released-init demo-released-transpile demo-released-compile demo-released-run

demo-released-check:
	@test -x "$(ZIGTSC_RELEASED)" || \
		(echo "error: released zigtsc not found — install via 'brew install zigtsc' or install.sh" && exit 1)
	@echo "Testing released binary: $(ZIGTSC_RELEASED)"

demo-released-init:
	rm -rf /tmp/demo-released && \
	mkdir -p /tmp/demo-released && \
	$(ZIGTSC_RELEASED) init /tmp/demo-released

demo-released-transpile:
	$(ZIGTSC_RELEASED) transpile /tmp/demo-released/src/main.ts

demo-released-compile:
	$(ZIGTSC_RELEASED) compile /tmp/demo-released/src/zigtscout

demo-released-run:
	$(ZIGTSC_RELEASED) run /tmp/demo-released/zig-out/bin/main && \
	$(ZIGTSC_RELEASED) run /tmp/demo-released/zig-out/wasm/main.wasm

# ── test-all ───────────────────────────────────────────────────────────────────

# Verify both the local build and the installed release work end-to-end
test-all: all demo-released

upgrade:
	brew update && brew upgrade zigtsc

website:
	npm --prefix www run dev

# Ship: release, wait for CI to finish, then upgrade the local install.
# Usage: make ship          (auto-bumps minor)
#        make ship V=1.0.0  (explicit version)
ship: release
	@command -v gh > /dev/null 2>&1 || \
		(echo "error: gh CLI not found — install with: brew install gh" && exit 1)
	@echo "Waiting for release workflow to appear..."
	@sleep 5
	gh run watch $$(gh run list --workflow=release.yml --limit=1 --json databaseId -q '.[0].databaseId') --exit-status
	$(MAKE) upgrade

.PHONY: all build clean release demo demo-init demo-transpile demo-compile demo-run \
        demo-released demo-released-check demo-released-init demo-released-transpile \
        demo-released-compile demo-released-run test-all website upgrade ship
