# Makefile for ZigTSC project

# Default target
all: executable clean init transpile compile run

# Make scripts executable
executable:
	chmod -R +x .

# Clean Zig cache and output
clean:
	cd /Users/nathanjmorton/codes/zigtsc && rm -rf .zig-cache/ zig-out/ zig-pkg/ 

# Initialize project in temp folder
init:
	rm -rf /tmp/demo && \
	mkdir -p /tmp/demo && \
	cd /tmp/demo && \
	zigtsc init .

# Transpile TypeScript
transpile:
	cd /tmp/demo && \
	zigtsc transpile src/main.ts

# Compile
compile:
	cd /tmp/demo && \
	zigtsc compile src/zigtscout

# Run the compiled binaries
run:
	cd /tmp/demo && \
	zigtsc run zig-out/bin/main && \
	zigtsc run zig-out/wasm/main.wasm

# Release: bump minor version, commit, tag, push. CI does the rest.
# Usage: make release          (auto-bumps minor, e.g. 0.5.0 → 0.6.0)
#        make release V=1.0.0  (explicit version)
release:
	./scripts/release.sh $(V)

.PHONY: all executable clean init transpile compile run release
