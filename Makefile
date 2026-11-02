.DEFAULT_GOAL := help

SHELL := /bin/bash
GLEAM ?= gleam
NPM   ?= npm
NODE  ?= node
PORT  ?= 3000
HOST  ?= 0.0.0.0

.PHONY: help build dev test check format deps run preview clean

help:
	@echo "sid-to-skode Makefile targets:"
	@echo "  make help         Show this help message"
	@echo "  make build        Compile Gleam and build production web bundle into dist/"
	@echo "  make dev          Start Vite dev server on $(HOST):$(PORT)"
	@echo "  make run          Alias for 'make dev'"
	@echo "  make test         Run test suite via Gleam JavaScript target"
	@echo "  make check        Verify Gleam types and compilation"
	@echo "  make format       Format all Gleam source and test files"
	@echo "  make deps         Download Gleam packages and install npm dependencies"
	@echo "  make preview      Preview production build in dist/ on $(HOST):$(PORT)"
	@echo "  make clean        Remove build and dist artifacts"

deps:
	mise exec -- gleam deps download
	mise exec -- npm install

build:
	mise exec -- gleam build --target javascript
	mise exec -- npm run build

dev:
	mise exec -- gleam build --target javascript
	mise exec -- npx vite --host $(HOST) --port $(PORT)

run: dev

preview:
	mise exec -- npx vite preview --host $(HOST) --port $(PORT)

test:
	mise exec -- gleam test --target javascript

check:
	mise exec -- gleam check

format:
	mise exec -- gleam format

clean:
	rm -rf dist build/dev
