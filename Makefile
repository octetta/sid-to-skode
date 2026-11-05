.DEFAULT_GOAL := help

SHELL := /bin/bash
GLEAM ?= gleam
NPM   ?= npm
NODE  ?= node
PORT  ?= 3000
HOST  ?= 0.0.0.0
export BROWSER ?= firefox

CC    ?= gcc
ESBUILD ?= npx esbuild
VENDOR_DIR  := .vendor/quickjs
CLI_BIN     := bin/sid2skode
CLI_ENTRY   := build/dev/javascript/sid_to_skode/cli.mjs
CLI_BUNDLE  := dist/sid2skode.mjs
CLI_WRAPPER := dist/wrapper.c

.PHONY: help build dev test check format deps run preview clean start siddump-wasm cli test-cli

help:
	@echo "sid-to-skode Makefile targets:"
	@echo "  make help         Show this help message"
	@echo "  make cli          Build command-line converter (bin/sid2skode)"
	@echo "  make test-cli     Run verification tests on bin/sid2skode"
	@echo "  make build        Compile Gleam and build production web bundle into dist/"
	@echo "  make dev          Start Vite dev server on $(HOST):$(PORT) and open in Firefox"
	@echo "  make run          Alias for 'make dev'"
	@echo "  make start        Alias for 'make dev'"
	@echo "  make test         Run test suite via Gleam JavaScript target"
	@echo "  make check        Verify Gleam types and compilation"
	@echo "  make format       Format all Gleam source and test files"
	@echo "  make deps         Download Gleam packages and install npm dependencies"
	@echo "  make siddump-wasm Compile siddump C source to WebAssembly"
	@echo "  make preview      Preview production build in dist/ on $(HOST):$(PORT)"
	@echo "  make clean        Remove build and dist artifacts"

siddump-wasm:
	@echo "==> Compiling siddump to WebAssembly with emcc..."
	mise exec -- emcc c_src/siddump/siddump.c c_src/siddump/cpu.c -O2 -s MODULARIZE=1 -s EXPORT_ES6=1 -s FORCE_FILESYSTEM=1 -s EXPORTED_RUNTIME_METHODS='["callMain","FS"]' -o vendor/siddump_wasm.js
	cp vendor/siddump_wasm.js vendor/siddump_wasm.wasm public/vendor/

deps:
	mise exec -- gleam deps download
	mise exec -- npm install

build:
	@echo "==> Compiling Gleam code to JavaScript..."
	mise exec -- gleam build --target javascript
	@echo "==> Bundling with Vite for production..."
	mise exec -- npm run build

dev:
	@echo "==> Compiling Gleam and launching Vite dev server with Firefox..."
	mise exec -- gleam build --target javascript
	mise exec -- npx vite --host $(HOST) --open --port $(PORT)

run: dev
start: dev

preview: build
	@echo "==> Launching production preview on $(HOST):$(PORT) with Firefox..."
	mise exec -- npx vite preview --host $(HOST) --open --port $(PORT)

test:
	mise exec -- gleam test --target javascript

check:
	mise exec -- gleam check

format:
	mise exec -- gleam format

clean:
	rm -rf dist build/dev

$(VENDOR_DIR)/qjsc:
	@mkdir -p .vendor
	@if [ ! -d "$(VENDOR_DIR)" ]; then \
		echo "==> Cloning QuickJS (no git submodules)..."; \
		git clone --depth 1 https://github.com/bellard/quickjs.git $(VENDOR_DIR); \
	fi
	@echo "==> Compiling QuickJS (qjsc and libquickjs.a)..."
	$(MAKE) -C $(VENDOR_DIR) qjsc libquickjs.a

$(CLI_BIN): $(VENDOR_DIR)/qjsc
	@mkdir -p bin dist
	@echo "==> Compiling Gleam code to JavaScript..."
	mise exec -- gleam build --target javascript
	@echo "==> Bundling CLI with esbuild..."
	$(ESBUILD) $(CLI_ENTRY) \
		--bundle \
		--format=esm \
		--platform=neutral \
		--external:std \
		--external:os \
		--external:siddump_native \
		--footer:js="main();" \
		--outfile=$(CLI_BUNDLE)
	@echo "==> Generating QuickJS C bytecode wrapper..."
	$(VENDOR_DIR)/qjsc -m -e -M siddump_native,siddump_native -o $(CLI_WRAPPER) $(CLI_BUNDLE)
	@echo "==> Compiling standalone native CLI executable with direct C linkage (-Os -s)..."
	$(CC) -Os -s \
		-I$(VENDOR_DIR) \
		-Ic_src \
		-Ic_src/siddump \
		$(CLI_WRAPPER) \
		c_src/siddump/siddump.c \
		c_src/siddump/cpu.c \
		c_src/siddump_qjs.c \
		$(VENDOR_DIR)/libquickjs.a \
		-lm -ldl -o $(CLI_BIN)
	@echo "==> Standalone native CLI binary ready at $(CLI_BIN):"
	@ls -lh $(CLI_BIN)

cli: $(CLI_BIN)

test-cli: $(CLI_BIN)
	@echo "==> Testing bin/sid2skode with --help..."
	./bin/sid2skode --help
	@echo "==> Testing bin/sid2skode with --version..."
	./bin/sid2skode --version
	@echo "==> Testing bin/sid2skode conversion on public/demos/commando.sid..."
	./bin/sid2skode public/demos/commando.sid -t 3 -o /tmp/commando_test.sk
	@head -n 20 /tmp/commando_test.sk
	@rm -f /tmp/commando_test.sk
	@echo "==> Testing bin/sid2skode across all 9 demo modules in public/demos/..."
	@for f in public/demos/*.sid; do \
		./bin/sid2skode "$$f" -t 2 -o /tmp/test_tune.sk > /dev/null || exit 1; \
		rm -f /tmp/test_tune.sk; \
	done
	@echo "==> All native CLI tests passed successfully!"
