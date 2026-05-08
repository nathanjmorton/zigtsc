# Makefile for ZigTSC project

ZIGTSC := ./zig-out/bin/zigtsc

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

website:
	npm --prefix www run dev

.PHONY: all build clean release demo demo-init demo-transpile demo-compile demo-run website
