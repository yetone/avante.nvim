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
BUILD_FROM_SOURCE := false

all: luajit

luajit: $(BUILD_DIR)/tiktoken_core.$(EXT)
lua51: $(BUILD_DIR)/tiktoken_core-lua51.$(EXT)

define build_from_source
	if [ -d "$(BUILD_DIR)/lua-tiktoken-temp" ]; then rm -rf $(BUILD_DIR)/lua-tiktoken-temp; fi
	git clone --branch v0.2.2 --depth 1 https://github.com/gptlang/lua-tiktoken.git $(BUILD_DIR)/lua-tiktoken-temp
	cd $(BUILD_DIR)/lua-tiktoken-temp && cargo build --features=$1
	cp $(BUILD_DIR)/lua-tiktoken-temp/target/debug/libtiktoken_core.$(EXT) $(BUILD_DIR)/tiktoken_core.$(EXT)
	rm -rf $(BUILD_DIR)/lua-tiktoken-temp
endef

$(BUILD_DIR)/tiktoken_core.$(EXT): $(BUILD_DIR)
	$(call build_from_source,luajit)
$(BUILD_DIR)/tiktoken_core-lua51.$(EXT): $(BUILD_DIR)
	$(call build_from_source,lua51)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)

luacheck:
	luacheck `find -name "*.lua"` --codes

stylecheck:
	stylua --check lua/

stylefix:
	stylua lua/
