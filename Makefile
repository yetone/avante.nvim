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

all: luajit

luajit: $(BUILD_DIR)/libavante_tokenizers.$(EXT)
lua51: $(BUILD_DIR)/libavante_tokenizers-lua51.$(EXT)
lua52: $(BUILD_DIR)/libavante_tokenizers-lua52.$(EXT)
lua53: $(BUILD_DIR)/libavante_tokenizers-lua53.$(EXT)
lua54: $(BUILD_DIR)/libavante_tokenizers-lua54.$(EXT)

define build_from_source
	cargo build --release --features=$1
	cp target/release/libavante_tokenizers.$(EXT) $(BUILD_DIR)/avante_tokenizers.$(EXT)
endef

$(BUILD_DIR)/libavante_tokenizers.$(EXT): $(BUILD_DIR)
	$(call build_from_source,luajit)
$(BUILD_DIR)/libavante_tokenizers-lua51.$(EXT): $(BUILD_DIR)
	$(call build_from_source,lua51)
$(BUILD_DIR)/libavante_tokenizers-lua52.$(EXT): $(BUILD_DIR)
	$(call build_from_source,lua52)
$(BUILD_DIR)/libavante_tokenizers-lua53.$(EXT): $(BUILD_DIR)
	$(call build_from_source,lua53)
$(BUILD_DIR)/libavante_tokenizers-lua54.$(EXT): $(BUILD_DIR)
	$(call build_from_source,lua54)

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
