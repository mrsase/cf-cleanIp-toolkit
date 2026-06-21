VERSION ?= $(shell cat VERSION 2>/dev/null || echo "1.0.0")
PROJECT  = cf-cleanIp-toolkit
SHELL    = /usr/bin/env bash

.DEFAULT_GOAL := help

.PHONY: help install build release clean lint check version

help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[0;36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## run the install script (download or compile, setup PATH)
	./install.sh

build: ## compile cfst + senpaiscanner from upstream source for current arch
	./scripts/build-scanners.sh

release: ## build release tarballs for all platforms (use before publishing)
	./scripts/build-scanners.sh --all --package

release/cf-cleanIp-toolkit-$(VERSION)-%.tar.gz: ## build a single-platform release tarball
	@os_arch="$*"; \
	os=$${os_arch%-*}; arch=$${os_arch#*-}; \
	echo "Building $$os/$$arch..."; \
	./scripts/build-scanners.sh --os "$$os" --arch "$$arch" --package --dest "$(CURDIR)/release"

clean: ## remove compiled binaries and release tarballs
	rm -f bin/cfst bin/senpaiscanner
	rm -rf release/
	@echo "[clean] done"

lint: ## check shell scripts with shellcheck
	@if command -v shellcheck &>/dev/null; then \
		shellcheck cf-cleanIp-toolkit install.sh scripts/*.sh launchd/*.plist 2>/dev/null || true; \
		echo "[lint] done"; \
	else \
		echo "[lint] shellcheck not installed — skipping"; \
	fi

check: ## verify the project is healthy
	@echo "[check] cfst:  $$(test -x bin/cfst && (bin/cfst -v 2>&1 | head -1) || echo MISSING)"
	@echo "[check] senpai: $$(test -x bin/senpaiscanner && echo present || echo MISSING)"
	@echo "[check] db:    $$(test -f db/clean_ips.db && du -h db/clean_ips.db | cut -f1 || echo MISSING)"
	@echo "[check] ranges: v4=$$(wc -l < data/ip.txt 2>/dev/null || echo 0)  v6=$$(wc -l < data/ipv6.txt 2>/dev/null || echo 0)"

version: ## show version info
	@./scripts/version.sh
