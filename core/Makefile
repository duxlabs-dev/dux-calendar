BINARY_NAME=dcal
SOURCE_DIR=cmd/dcal
BUILD_DIR=bin
SHELL_SRC=../quickshell
EMBED_DIR=internal/shellembed/dist
COMPLETIONS_DIR=$(BUILD_DIR)/completions
PREFIX ?= /usr/local
INSTALL_DIR=$(PREFIX)/bin
BASHCOMP_DIR=$(PREFIX)/share/bash-completion/completions
ZSHCOMP_DIR=$(PREFIX)/share/zsh/site-functions
FISHCOMP_DIR=$(PREFIX)/share/fish/vendor_completions.d

GO=go

BASE_VERSION=$(or $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'),0.0.0)
COMMIT_COUNT=$(shell git rev-list --count HEAD 2>/dev/null || echo "0")
COMMIT_HASH=$(shell git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
VERSION?=$(BASE_VERSION)+git$(COMMIT_COUNT).$(COMMIT_HASH)
BUILD_TIME?=$(shell date -u '+%Y-%m-%d_%H:%M:%S')
COMMIT?=$(COMMIT_HASH)

BUILD_LDFLAGS=-ldflags='-s -w -X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME) -X main.Commit=$(COMMIT)'

.PHONY: all build dev qtbase clean-qtbase sync-shell completions install install-completions uninstall clean test cover fmt vet deps generate migrate migrate-checksum mocks help

all: build completions

# QTBASE=1 builds the quickshell runtime from the dux-qt-base submodule and embeds it in dcal as libdux-qt-base.so,
# which `dcal qs` dlopens. With the default QTBASE=0, `dcal qs` dlopens an installed libdux-qt-base.so.0
# (next to dcal or in the system library dirs, e.g. a dux-qt-base package). `dcal run --qs-child` runs upstream qs instead.
QTBASE ?= 0
QTBASE_SRC ?= ../dux-qt-base
QTBASE_BUILD ?= build/dux-qt-base
QTBASE_LIB = $(QTBASE_BUILD)/src/libdux-qt-base.so.0
QTBASE_EMBED_DIR = internal/qtbaseembed/lib
ifeq ($(QTBASE),0)
QTBASE_DEP =
QTBASE_TAG =
else
QTBASE_DEP = qtbase
QTBASE_TAG = withqtbase
endif

qtbase:
	@test -f $(QTBASE_SRC)/CMakeLists.txt || { echo "dux-qt-base missing: run git submodule update --init"; exit 1; }
	@test -f $(QTBASE_BUILD)/build.ninja || cmake -S $(QTBASE_SRC) -B $(QTBASE_BUILD) -GNinja -DCMAKE_BUILD_TYPE=Release \
		-DDISTRIBUTOR=$(BINARY_NAME)-source -DGIT_REVISION=$$(git -C $(QTBASE_SRC) rev-parse --short=8 HEAD 2>/dev/null || echo unknown)
	cmake --build $(QTBASE_BUILD)
	@mkdir -p $(QTBASE_EMBED_DIR)
	@strip --strip-unneeded -o $(QTBASE_EMBED_DIR)/libdux-qt-base.so.0 $(QTBASE_LIB)
	@sha256sum $(QTBASE_EMBED_DIR)/libdux-qt-base.so.0 | cut -c1-16 > $(QTBASE_EMBED_DIR)/.dankrev

clean-qtbase:
	@rm -rf $(QTBASE_BUILD)

# Copy the quickshell UI into the embed dir (gitignored) so tagged builds
# can bake it into the binary. Dev-only files are stripped. tar -h dereferences
# the DCommon submodule symlink; go:embed rejects symlinks. .qmlls.ini is
# excluded at copy time: it's a symlink into the quickshell runtime VFS and
# dereferencing it fails whenever the shell isn't running.
sync-shell:
	@test -f $(SHELL_SRC)/DCommon/Widgets/DIcon.qml || { echo "DCommon missing: run git submodule update --init"; exit 1; }
	@rm -rf $(EMBED_DIR)
	@mkdir -p $(EMBED_DIR)
	@tar -C $(SHELL_SRC) --exclude=.qmlls.ini -chf - . | tar -C $(EMBED_DIR) -xf -
	@rm -rf $(EMBED_DIR)/scripts $(EMBED_DIR)/.claude
	@rm -f $(EMBED_DIR)/translations/extract_translations.py

build: sync-shell $(QTBASE_DEP)
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 $(GO) build -tags 'withshell $(QTBASE_TAG)' $(BUILD_LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) ./$(SOURCE_DIR)
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME)"

dev: $(QTBASE_DEP)
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 $(GO) build -tags '$(QTBASE_TAG)' -o $(BUILD_DIR)/$(BINARY_NAME) ./$(SOURCE_DIR)

completions: build
	@mkdir -p $(COMPLETIONS_DIR)
	@$(BUILD_DIR)/$(BINARY_NAME) completion bash > $(COMPLETIONS_DIR)/$(BINARY_NAME)
	@$(BUILD_DIR)/$(BINARY_NAME) completion zsh > $(COMPLETIONS_DIR)/_$(BINARY_NAME)
	@$(BUILD_DIR)/$(BINARY_NAME) completion fish > $(COMPLETIONS_DIR)/$(BINARY_NAME).fish
	@$(BUILD_DIR)/$(BINARY_NAME) completion powershell > $(COMPLETIONS_DIR)/$(BINARY_NAME).ps1
	@echo "Completions written to $(COMPLETIONS_DIR)"

install: install-completions
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME) $(DESTDIR)$(INSTALL_DIR)/$(BINARY_NAME)

install-completions:
	@install -D -m 644 $(COMPLETIONS_DIR)/$(BINARY_NAME) $(DESTDIR)$(BASHCOMP_DIR)/$(BINARY_NAME)
	@install -D -m 644 $(COMPLETIONS_DIR)/_$(BINARY_NAME) $(DESTDIR)$(ZSHCOMP_DIR)/_$(BINARY_NAME)
	@install -D -m 644 $(COMPLETIONS_DIR)/$(BINARY_NAME).fish $(DESTDIR)$(FISHCOMP_DIR)/$(BINARY_NAME).fish

uninstall:
	@rm -f $(DESTDIR)$(INSTALL_DIR)/$(BINARY_NAME)
	@rm -f $(DESTDIR)$(BASHCOMP_DIR)/$(BINARY_NAME)
	@rm -f $(DESTDIR)$(ZSHCOMP_DIR)/_$(BINARY_NAME)
	@rm -f $(DESTDIR)$(FISHCOMP_DIR)/$(BINARY_NAME).fish

clean:
	@rm -rf $(BUILD_DIR) $(EMBED_DIR) $(QTBASE_EMBED_DIR)

test:
	CGO_ENABLED=0 $(GO) test ./...

cover:
	CGO_ENABLED=0 $(GO) test -coverprofile=coverage.out ./...
	$(GO) tool cover -func=coverage.out

fmt:
	$(GO) fmt ./...

vet:
	CGO_ENABLED=0 $(GO) vet ./...

deps:
	$(GO) mod tidy
	$(GO) mod download

generate:
	$(GO) generate ./ent/...

# Create a versioned migration by diffing the Ent schema: make migrate name=add_foo
migrate:
	@if [ -z "$(name)" ]; then echo "usage: make migrate name=<migration_name>"; exit 1; fi
	$(GO) run -mod=mod ./ent/migrate/main.go -name=$(name)

# Rebuild ent/migrate/migrations/atlas.sum after editing a migration by hand.
migrate-checksum:
	$(GO) run -mod=mod ./ent/migrate/main.go -checksum

mocks:
	mockery

help:
	@echo "Targets: build dev qtbase clean-qtbase sync-shell completions install install-completions uninstall clean test cover fmt vet deps generate migrate migrate-checksum mocks"
	@echo "QTBASE=1 embeds the dux-qt-base runtime from the submodule; by default dcal needs an installed dux-qt-base"
