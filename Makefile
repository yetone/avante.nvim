UNAME := $(shell uname)
ARCH := $(shell uname -m)

ifeq ($(UNAME), Linux)
	OS := linux
	EXT := so
else ifeq ($(UNAME), Darwin)
	OS := macOS
	EXT := dylib
else
	$(error Unsupported operating system: $(UNAME))
endif

LUA_VERSIONS := luajit lua51

BUILD_DIR := build
BUILD_FROM_SOURCE ?= false
TARGET_LIBRARY ?= all

all: luajit

define make_definitions
ifeq ($(BUILD_FROM_SOURCE),true)
ifeq ($(TARGET_LIBRARY), all)
$1: $(BUILD_DIR)/libAvanteTokenizers-$1.$(EXT) $(BUILD_DIR)/libAvanteTemplates-$1.$(EXT)
else ifeq ($(TARGET_LIBRARY), tokenizers)
$1: $(BUILD_DIR)/libAvanteTokenizers-$1.$(EXT)
else ifeq ($(TARGET_LIBRARY), templates)
$1: $(BUILD_DIR)/libAvanteTemplates-$1.$(EXT)
else
	$$(error TARGET_LIBRARY must be one of all, tokenizers, templates)
endif
else
$1:
	LUA_VERSION=$1 bash ./build.sh
endif
endef

$(foreach lua_version,$(LUA_VERSIONS),$(eval $(call make_definitions,$(lua_version))))

define build_package
$1-$2:
	cargo build --release --features=$1 -p avante-$2
	cp target/release/libavante_$2.$(EXT) $(BUILD_DIR)/avante_$2.$(EXT)
endef

define build_targets
$(BUILD_DIR)/libAvanteTokenizers-$1.$(EXT): $(BUILD_DIR) $1-tokenizers
$(BUILD_DIR)/libAvanteTemplates-$1.$(EXT): $(BUILD_DIR) $1-templates
endef

$(foreach lua_version,$(LUA_VERSIONS),$(eval $(call build_package,$(lua_version),tokenizers)))
$(foreach lua_version,$(LUA_VERSIONS),$(eval $(call build_package,$(lua_version),templates)))
$(foreach lua_version,$(LUA_VERSIONS),$(eval $(call build_targets,$(lua_version))))

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

clean:
	@rm -rf $(BUILD_DIR)

luacheck:
	@luacheck `find -name "*.lua"` --codes

stylecheck:
	@stylua --check lua/ plugin/

stylefix:
	@stylua lua/ plugin/

.PHONY: ruststylecheck
ruststylecheck:
	@rustup component add rustfmt 2> /dev/null
	@cargo fmt --all -- --check

.PHONY: rustlint
rustlint:
	@rustup component add clippy 2> /dev/null
	@cargo clippy -F luajit --all -- -F clippy::dbg-macro -D warnings
