VERSION ?= $(shell cat VERSION 2>/dev/null || echo "1.0.0")
PROJECT  = tunnel
SHELL    = /usr/bin/env bash

.DEFAULT_GOAL := help

.PHONY: help install build release clean lint check version

help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "$(CYAN)%-20s$(NC) %s\n", $$1, $$2}'
NC  = \033[0m
CYAN= \033[0;36m

install: ## run the install script (detects arch, downloads deps, sets up PATH)
	./install.sh

build: ## download scanner binaries for the current architecture
	./scripts/prepare-release.sh --current-only

release: ## download binaries for all supported architectures (for GitHub releases)
	./scripts/prepare-release.sh --all

release/tunnel-$(VERSION)-%.tar.gz: ## build a single release tarball (use: make release/tunnel-1.0.0-darwin-amd64.tar.gz)
	@os_arch="$*"; \
	os=$${os_arch%-*}; arch=$${os_arch#*-}; \
	echo "Packaging $$os/$$arch..."; \
	./scripts/prepare-release.sh --os "$$os" --arch "$$arch"

clean: ## remove downloaded binaries
	rm -f bin/cfst bin/senpaiscanner
	@echo "[clean] Binaries removed. Re-run 'make build' or 'make install' to fetch them."

lint: ## check shell scripts with shellcheck
	@if command -v shellcheck &>/dev/null; then \
		shellcheck tunnel install.sh scripts/*.sh launchd/*.plist 2>/dev/null || true; \
		echo "[lint] done"; \
	else \
		echo "[lint] shellcheck not installed — skipping (brew install shellcheck)"; \
	fi

check: ## verify the project is in a healthy state
	@echo "[check] cfst:  $$(test -x bin/cfst && (bin/cfst -v 2>&1 | head -1) || echo MISSING)"
	@echo "[check] senpai: $$(test -x bin/senpaiscanner && echo present || echo MISSING)"
	@echo "[check] db:    $$(test -f db/clean_ips.db && du -h db/clean_ips.db | cut -f1 || echo MISSING)"
	@echo "[check] ranges: v4=$$(wc -l < data/ip.txt 2>/dev/null || echo 0)  v6=$$(wc -l < data/ipv6.txt 2>/dev/null || echo 0)"

version: ## show version info
	@echo "$(PROJECT) v$(VERSION)"
	@echo "os/arch: $$(uname -s)/$$(uname -m)"
