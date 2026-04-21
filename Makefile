BIN_DIR    := $(CURDIR)/bin

# Platform detection
UNAME_S    := $(shell uname -s | tr '[:upper:]' '[:lower:]')
UNAME_M    := $(shell uname -m)

ifeq ($(UNAME_M),arm64)
  ARCH := aarch64
else ifeq ($(UNAME_M),aarch64)
  ARCH := aarch64
else
  ARCH := $(UNAME_M)
endif

ifeq ($(UNAME_S),darwin)
  DPRINT_TARGET := $(ARCH)-apple-darwin
else ifeq ($(UNAME_S),linux)
  DPRINT_TARGET := $(ARCH)-unknown-linux-gnu
endif

# Tool versions
DPRINT_VERSION := 0.54.0

# Tool paths
DPRINT := $(BIN_DIR)/dprint

TOOLS := $(DPRINT)

.PHONY: tools fmt-md check-md clean

tools: $(TOOLS)

DPRINT_RELEASE_URL := https://github.com/dprint/dprint/releases/download/$(DPRINT_VERSION)/dprint-$(DPRINT_TARGET).zip

$(DPRINT):
	@mkdir -p $(BIN_DIR)
	@echo "Downloading dprint $(DPRINT_VERSION) for $(DPRINT_TARGET)..."
	@curl -fsSL "$(DPRINT_RELEASE_URL)" -o $(BIN_DIR)/dprint.zip
	@unzip -oq $(BIN_DIR)/dprint.zip -d $(BIN_DIR)
	@rm $(BIN_DIR)/dprint.zip
	@chmod +x $(DPRINT)
	@echo "Installed dprint -> $(DPRINT)"

fmt-md: $(DPRINT)
	$(DPRINT) fmt

check-md: $(DPRINT)
	$(DPRINT) check

clean:
	rm -rf $(BIN_DIR)
