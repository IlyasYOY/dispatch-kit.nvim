STYLUA ?= stylua
LUACHECK ?= luacheck
NVIM ?= nvim
NVIM_VERSION ?=
DEPDIR ?= .test-deps
CURL ?= curl -fL --retry 5 --retry-delay 5 --retry-connrefused --create-dirs
TEST_HOME ?= $(CURDIR)/.test-home
TEST_ENV := DISPATCH_KIT_TEST_HOME=$(TEST_HOME) XDG_CONFIG_HOME=$(TEST_HOME)/config XDG_DATA_HOME=$(TEST_HOME)/data XDG_CACHE_HOME=$(TEST_HOME)/cache XDG_STATE_HOME=$(TEST_HOME)/state
LUA_DIRS := lua plugin tests

ifeq ($(shell uname -s),Darwin)
  ifeq ($(shell uname -m),arm64)
    NVIM_ARCH ?= macos-arm64
  else
    NVIM_ARCH ?= macos-x86_64
  endif
else
  NVIM_ARCH ?= linux-x86_64
endif

ifneq ($(NVIM_VERSION),)
  NVIM_DIR := $(DEPDIR)/nvim-$(NVIM_VERSION)-$(NVIM_ARCH)
  NVIM_STAMP := $(NVIM_DIR)/.installed
  NVIM_TARBALL := $(NVIM_DIR).tar.gz
  NVIM_URL := https://github.com/neovim/neovim/releases/download/$(NVIM_VERSION)/nvim-$(NVIM_ARCH).tar.gz
  TEST_NVIM := $(NVIM_DIR)/nvim-$(NVIM_ARCH)/bin/nvim
  TEST_NVIM_DEPS := $(NVIM_STAMP)
else
  TEST_NVIM := $(NVIM)
  TEST_NVIM_DEPS :=
endif

.PHONY: help nvim test test-verbose format-check lint format help-check check clean

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make check       Run formatting, lint, help, and tests.' \
		'  make test        Run the isolated Neovim test suite.' \
		'  make format      Format Lua sources.' \
		'  make clean       Remove downloaded test dependencies and state.'

nvim: $(TEST_NVIM_DEPS)

ifneq ($(NVIM_VERSION),)
$(NVIM_STAMP):
	$(CURL) $(NVIM_URL) -o $(NVIM_TARBALL)
	rm -rf $(NVIM_DIR)
	mkdir -p $(NVIM_DIR)
	tar -xf $(NVIM_TARBALL) -C $(NVIM_DIR)
	rm -f $(NVIM_TARBALL)
	touch $@
endif

test: $(TEST_NVIM_DEPS)
	@$(TEST_ENV) $(TEST_NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua require('tests.runner').run()" -c qa

test-verbose: $(TEST_NVIM_DEPS)
	@$(TEST_ENV) $(TEST_NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua require('tests.runner').run({ verbose = true })" -c qa

format-check:
	$(STYLUA) --color always --check $(LUA_DIRS)

lint:
	$(LUACHECK) $(LUA_DIRS)
	$(STYLUA) --color always --check $(LUA_DIRS)

format:
	$(STYLUA) $(LUA_DIRS)

help-check:
	@mkdir -p .test-work/doc
	@cp doc/dispatch-kit.txt .test-work/doc/dispatch-kit.txt
	@$(NVIM) --clean --headless -u NONE \
		-c "helptags $(CURDIR)/.test-work/doc" -c qa

check: format-check lint test help-check

clean:
	rm -rf $(DEPDIR) $(TEST_HOME) .test-work
