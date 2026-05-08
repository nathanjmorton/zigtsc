# Makefile for ZigTSC project

# Default target
all: executable clean init transpile compile run

# Make scripts executable
executable:
	chmod -R +x .

# Clean Zig cache and output
clean:
	cd /Users/nathanjmorton/codes/zigtsc && rm -rf .zig-cache/ zig-out/ zig-pkg/ temp

# Initialize project in temp folder
init:
	cd /Users/nathanjmorton/codes/zigtsc && \
	rm -rf temp && \
	mkdir -p temp && \
	cd temp && \
	zigtsc init .

# Transpile TypeScript
transpile:
	cd /Users/nathanjmorton/codes/zigtsc/temp && \
	zigtsc transpile src/main.ts

# Compile
compile:
	cd /Users/nathanjmorton/codes/zigtsc/temp && \
	zigtsc compile src/zigtscout

# Run the compiled binaries
run:
	cd /Users/nathanjmorton/codes/zigtsc/temp && \
	zigtsc run zig-out/bin/main && \
	zigtsc run zig-out/wasm/main.wasm

.PHONY: all executable clean init transpile compile run