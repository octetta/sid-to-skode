.DEFAULT_GOAL := help

SHELL := /bin/bash
GLEAM ?= gleam
NPM   ?= npm
NODE  ?= node
PORT  ?= 3000
HOST  ?= 0.0.0.0
export BROWSER ?= firefox

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

cli:
	@echo "==> Building CLI executable..."
	mise exec -- gleam build --target javascript
	@chmod +x bin/sid2skode bin/sid2skode.mjs
	@echo "==> CLI executable ready at bin/sid2skode"

test-cli: cli
	@echo "==> Testing bin/sid2skode with --help..."
	./bin/sid2skode --help
	@echo "==> Testing bin/sid2skode conversion on public/demos/commando.sid..."
	./bin/sid2skode public/demos/commando.sid -t 3 -o /tmp/commando_test.sk
	@rm -f /tmp/commando_test.sk
	@echo "==> CLI tests passed!"
